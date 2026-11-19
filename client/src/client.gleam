import gleam/dynamic/decode
import gleam/float
import gleam/http/response.{type Response}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri.{type Uri}
import lustre
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_websocket as ws
import modem
import rsvp
import youid/uuid.{type Uuid}

import client/game_view.{type Msg as GameMsg}
import client/lobby_view.{type Msg as LobbyMsg}
import client/local_data.{LocalData}
import client/shared.{
  type Context, type Route, Context, Finish as RouteFinish, Game as RouteGame,
  Lobby as RouteLobby, Start as RouteStart,
}
import client/start_view.{type Msg as StartMsg}
import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type AppEvent}
import shared/game.{type Game, Game} as app_game
import shared/player.{type Player, type PlayerGame, Player, PlayerGame} as app_player

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", [])

  Nil
}

// -----------------------------------------------
// Model -----------------------------------------
// -----------------------------------------------
type Model {
  Model(
    context: Context,
    dice_state: DiceState,
    errors: String,
    player_game: PlayerGame,
    start_model: start_view.Model,
    lobby_model: lobby_view.Model,
    game_model: game_view.Model,
  )
}

fn initial_route_effect(initial_route: Route) {
  use dispatch <- effect.from()
  dispatch(OnRouteChange(initial_route))
}

fn init(_) -> #(Model, Effect(Msg)) {
  let route =
    modem.initial_uri()
    |> result.map(fn(initial_uri) { uri.path_segments(initial_uri.path) })
    |> fn(path) {
      case path {
        Ok([""]) -> RouteStart
        Ok(["lobby", code]) -> RouteLobby(code)
        Ok(["game", code]) -> RouteGame(code)
        _ -> RouteStart
      }
    }
  let dice_state = dice.new_dice_state()
  let player = app_player.new_player()
  let game = app_game.empty_game()
  let player_game = app_player.new_player_game(player, game.code)

  let startup_effects = [
    ws.init("/ws", WsWrapper),
    modem.init(on_url_change),
    initial_route_effect(route),
    local_get_player_id(),
  ]

  let context =
    Context(ws: None, player:, current_route: route, game:, player_game:)

  #(
    Model(
      context:,
      dice_state:,
      errors: "",
      player_game:,
      start_model: start_view.new_model(),
      lobby_model: lobby_view.new_model(),
      game_model: game_view.new_model(),
    ),
    effect.batch(startup_effects),
  )
}

// -----------------------------------------------
// Update ----------------------------------------
// -----------------------------------------------

fn on_url_change(uri: Uri) -> Msg {
  case uri.path_segments(uri.path) {
    [""] -> OnRouteChange(RouteStart)
    ["lobby", code] -> OnRouteChange(RouteLobby(code))
    ["game", code] -> OnRouteChange(RouteGame(code))
    ["finish", code] -> OnRouteChange(RouteFinish(code))
    _ -> OnRouteChange(RouteStart)
  }
}

// get the player game from the player

type Msg {
  StartViewMsg(StartMsg)
  LobbyViewMsg(LobbyMsg)
  GameViewMsg(GameMsg)
  ServerReturnedPlayer(Result(Player, rsvp.Error(String)))
  WsWrapper(ws.WebSocketEvent)
  OnRouteChange(Route)
  ClientRequestPlayer(Uuid)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    StartViewMsg(start_msg) -> {
      let #(context, start_model, start_effect) =
        start_view.update(model.context, model.start_model, start_msg)

      #(
        Model(..model, context:, start_model:),
        start_effect |> effect.map(StartViewMsg),
      )
    }
    LobbyViewMsg(lobby_msg) -> {
      let #(context, lobby_model, lobby_effect) =
        lobby_view.update(model.context, model.lobby_model, lobby_msg)

      #(
        Model(..model, context:, lobby_model:),
        lobby_effect |> effect.map(LobbyViewMsg),
      )
    }
    GameViewMsg(game_msg) -> {
      let #(context, game_model, game_effect) =
        game_view.update(model.context, model.game_model, game_msg)

      #(
        Model(..model, context:, game_model:),
        game_effect |> effect.map(GameViewMsg),
      )
    }
    // Server Messages
    // Websocket Messages
    WsWrapper(event) -> handle_ws_event(model, event)
    // Routes
    OnRouteChange(route) -> {
      let context = Context(..model.context, current_route: route)
      case route {
        RouteLobby(_code) -> {
          let #(context, lobby_model, lobby_effect) =
            lobby_view.init(context, model.lobby_model)
          #(
            Model(..model, context:, lobby_model:),
            lobby_effect |> effect.map(LobbyViewMsg),
          )
        }
        _ -> #(Model(..model, context:), effect.none())
      }
    }
    // Other
    ClientRequestPlayer(player_id) -> {
      case player_id {
        id if id == uuid.nil -> {
          // post new id to server and save to local storage
          let new_id = uuid.v4()
          let body = app_player.player_to_json(Player(new_id, None))
          let url = "/api/player"

          #(
            model,
            rsvp.post(
              url,
              body,
              rsvp.expect_json(
                app_player.player_decoder(),
                ServerReturnedPlayer,
              ),
            ),
          )
        }
        id -> {
          // get player from server
          let url = "/api/player/" <> uuid.to_string(id)

          #(
            model,
            rsvp.get(
              url,
              rsvp.expect_json(
                app_player.player_decoder(),
                ServerReturnedPlayer,
              ),
            ),
          )
        }
      }
    }
    ServerReturnedPlayer(request_result) -> {
      case request_result {
        Ok(player) -> {
          let context = Context(..model.context, player:)
          #(Model(..model, context:), local_save_player_id(player.id))
        }
        Error(error) -> {
          io.println(
            "error from ServerReturnedPlayer: " <> string.inspect(error),
          )
          #(model, effect.none())
        }
      }
    }
  }
}

fn handle_ws_event(model: Model, ws_event: ws.WebSocketEvent) {
  case ws_event {
    ws.InvalidUrl -> panic
    ws.OnOpen(socket) -> #(
      Model(..model, context: Context(..model.context, ws: Some(socket))),
      effect.none(),
      // shared.send_event(
    //   Some(socket),
    //   events.ClientConnected(model.context.player),
    // ),
    )
    ws.OnTextMessage(message) -> {
      events.parse_event(message)
      |> handle_app_event(model)
    }
    ws.OnBinaryMessage(_msg) -> #(model, effect.none())
    ws.OnClose(_reason) -> #(model, effect.none())
  }
}

fn handle_app_event(event: AppEvent, model: Model) -> #(Model, Effect(Msg)) {
  case model.context.current_route {
    RouteLobby(_code) -> {
      let #(context, lobby_model, lobby_effect) =
        lobby_view.handle_app_event(model.context, model.lobby_model, event)

      #(
        Model(..model, context:, lobby_model:),
        lobby_effect |> effect.map(LobbyViewMsg),
      )
    }
    _ -> {
      io.println(
        string.inspect(model.context.current_route)
        <> " isn't expecting a ws message.",
      )
      #(model, effect.none())
    }
  }
}

//   case event {
//     events.UpdatedDiceState(dice_state) -> #(
//       Model(..model, dice_state:),
//       effect.none(),
//     )
//     events.ServerFoundPlayer(player) -> {
//       io.println("server found player: " <> string.inspect(player))
//       #(model, effect.none())
//     }
//     events.UpdatePlayerList(players) -> {
//       io.println("updataded player list with: " <> string.inspect(players))
//       #(model, effect.none())
//     }
//     _ -> {
//       io.println("unhandled event: " <> string.inspect(event))
//       #(model, effect.none())
//     }
//   }
// }

fn local_get_player_id() -> Effect(Msg) {
  use dispatch <- effect.from

  // get from localstorage
  let player_id = case local_data.get() {
    Ok(data) -> {
      data.player_id
    }
    Error(err) -> {
      io.println(string.inspect(err))
      uuid.nil
    }
  }
  dispatch(ClientRequestPlayer(player_id))
}

fn local_save_player_id(player_id: Uuid) {
  use _ <- effect.from

  local_data.save(LocalData(player_id:))
}

// -----------------------------------------------
// View ------------------------------------------
// -----------------------------------------------

fn view(model: Model) -> Element(Msg) {
  case model.context.current_route {
    RouteStart -> {
      start_view.view(model.context, model.start_model)
      |> element.map(StartViewMsg)
    }
    RouteLobby(_) -> {
      lobby_view.view(model.context, model.lobby_model)
      |> element.map(LobbyViewMsg)
    }
    RouteGame(_) ->
      game_view.view(model.context, model.game_model)
      |> element.map(GameViewMsg)
    RouteFinish(_) -> finish_view(model)
  }
}

fn finish_view(_model: Model) -> Element(Msg) {
  html.div([], [html.text("Finish view")])
}
