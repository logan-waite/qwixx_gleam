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
  let player_game = app_player.new_player_game(player.id, game.id)

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
  UserRolledDice
  UserToggledScoreBox(String)
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
    UserRolledDice -> #(
      model,
      shared.send_event(model.context.ws, events.RollDice),
    )
    UserToggledScoreBox(value) -> update_player_game(model, value)
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

// Dice

// Score Card
fn update_player_game(model: Model, value: String) {
  // asserting here because we defined the values we're splitting
  let assert [color, num_string] = string.split(value, "-")
  let assert Ok(number) = int.parse(num_string)
  // get the bitmask value
  let assert Ok(bit_float) = int.power(2, int.to_float(number - 1))
  let bit_value = float.round(bit_float)

  let player_game = case color {
    "red" ->
      PlayerGame(..model.player_game, red: model.player_game.red + bit_value)
    "yellow" ->
      PlayerGame(
        ..model.player_game,
        yellow: model.player_game.yellow + bit_value,
      )
    "green" ->
      PlayerGame(
        ..model.player_game,
        green: model.player_game.green + bit_value,
      )
    "blue" ->
      PlayerGame(..model.player_game, blue: model.player_game.blue + bit_value)
    _ -> {
      io.println("Error updating player game, received wrong color:" <> color)
      model.player_game
    }
  }
  io.println(
    "updated player game: "
    <> app_player.player_game_to_json(player_game) |> json.to_string(),
  )
  #(
    Model(..model, player_game:),
    shared.send_event(
      model.context.ws,
      events.PlayerUpdatedPlayerGame(player_game),
    ),
  )
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
    RouteGame(_) -> game_view(model)
    RouteFinish(_) -> finish_view(model)
  }
}

fn game_view(model: Model) -> Element(Msg) {
  html.div([], [
    html.button([event.on_click(UserRolledDice)], [html.text("Roll Dice")]),
    dice_tray(model.dice_state),
    score_card(model.player_game),
  ])
}

fn finish_view(_model: Model) -> Element(Msg) {
  html.div([], [html.text("Finish view")])
}

// Dice Tray
fn dice_tray(dice_state: DiceState) {
  html.div([], [
    html.ul([], [
      html.li([], [
        html.text("Red: " <> int.to_string(dice_state.red.value)),
      ]),
      html.li([], [
        html.text("Yellow: " <> int.to_string(dice_state.yellow.value)),
      ]),
      html.li([], [
        html.text("Blue: " <> int.to_string(dice_state.blue.value)),
      ]),
      html.li([], [
        html.text("Green: " <> int.to_string(dice_state.green.value)),
      ]),
      html.li([], [
        html.text("White 1: " <> int.to_string(dice_state.white_1.value)),
      ]),
      html.li([], [
        html.text("White 2: " <> int.to_string(dice_state.white_2.value)),
      ]),
    ]),
  ])
}

// Score Card
fn score_box(id, content, is_selected) {
  html.label([attr.for(id)], [
    html.input([
      attr.type_("checkbox"),
      attr.id(id),
      attr.value(id),
      attr.checked(is_selected),
      event.on_change(UserToggledScoreBox),
    ]),
    html.text(content),
  ])
}

fn score_row(color, bitmask) {
  let boxes =
    int.range(from: 13, to: 1, with: [], run: fn(acc, i: Int) {
      let assert Ok(exp) = int.power(2, int.to_float(i - 1))
      let value = float.round(exp) |> int.bitwise_and(bitmask)
      let is_selected = value > 0

      let num = int.to_string(i)
      { color <> "-" <> num }
      |> score_box(num, is_selected)
      |> list.prepend(acc, _)
    })

  html.div([], [html.text(color), ..boxes])
}

// fn bitmask_to_num_list(bitmask: Int) -> List(Int) {
//   int.range(from: 13, to: -1, with: [], fn(acc, i: Int) {
//     let exp = int.power(2, i)
//       case bitmask - exp {
//         0 -> {}
//         _ -> 
//     }
//   }
// }

fn score_card(game: PlayerGame) {
  html.div([], [
    score_row("red", game.red),
    score_row("yellow", game.yellow),
    score_row("green", game.green),
    score_row("blue", game.blue),
  ])
}
