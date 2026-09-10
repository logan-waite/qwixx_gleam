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
import youid/uuid

import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type AppEvent}
import shared/player.{type Player, type PlayerGame, Player, PlayerGame} as shared_player

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
    ws: Option(ws.WebSocket),
    current_route: Route,
    dice_state: DiceState,
    errors: String,
    player: Player,
    player_game: PlayerGame,
    temp_name: String,
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let route =
    modem.initial_uri()
    |> result.map(fn(initial_uri) { uri.path_segments(initial_uri.path) })
    |> fn(path) {
      case path {
        Ok([""]) -> Start
        Ok(["lobby"]) -> Lobby
        Ok(["game"]) -> Game
        _ -> Start
      }
    }
  let dice_state = dice.new_dice_state()
  let player = shared_player.new_player()
  let player_game = shared_player.new_player_game(player.id, uuid.v4())

  let startup_effects = [
    ws.init("ws", WsWrapper),
    modem.init(on_url_change),
    get_player_on_startup(),
  ]

  #(
    Model(
      ws: None,
      dice_state:,
      player:,
      errors: "",
      current_route: route,
      player_game:,
      temp_name: "",
    ),
    effect.batch(startup_effects),
  )
}

// -----------------------------------------------
// Update ----------------------------------------
// -----------------------------------------------

// Routes
type Route {
  Start
  Lobby
  Game
}

fn on_url_change(uri: Uri) -> Msg {
  case uri.path_segments(uri.path) {
    [""] -> OnRouteChange(Start)
    ["lobby"] -> OnRouteChange(Lobby)
    ["game"] -> OnRouteChange(Game)
    _ -> OnRouteChange(Start)
  }
}

type Msg {
  UserUpdatedName(String)
  UserSavedName
  UserRolledDice
  UserToggledScoreBox(String)
  ServerReturnedPlayer(Result(Player, rsvp.Error(String)))
  WsWrapper(ws.WebSocketEvent)
  OnRouteChange(Route)
  LocalStorageGet(Result(LocalData, Nil))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserUpdatedName(name) -> #(Model(..model, temp_name: name), effect.none())
    UserSavedName -> update_player_name(model)
    UserRolledDice -> #(model, send_event(model.ws, events.RollDice))
    UserToggledScoreBox(value) -> update_player_game(model, value)
    // Server Messages
    ServerReturnedPlayer(request_result) -> {
      case request_result {
        Ok(player) -> #(
          Model(..model, player:),
          save_local_data(LocalData(player.id)),
        )
        Error(error) -> {
          io.println(
            "error from ServerReturnedPlayer: " <> string.inspect(error),
          )
          #(model, effect.none())
        }
      }
    }
    // Websocket Messages
    WsWrapper(event) -> handle_ws_event(model, event)
    // Routes
    OnRouteChange(route) -> #(
      Model(..model, current_route: route),
      effect.none(),
    )
    // Other
    LocalStorageGet(local_data) -> {
      case local_data {
        Ok(data) -> {
          io.println("data: " <> string.inspect(data))
          #(
            Model(..model, player: Player(id: data.player_id, name: None)),
            effect.none(),
          )
        }
        Error(_) -> {
          let player_id = uuid.v4()
          let player = Player(..model.player, id: player_id)
          #(Model(..model, player:), effect.none())
        }
      }
    }
  }
}

fn handle_ws_event(model: Model, ws_event: ws.WebSocketEvent) {
  case ws_event {
    ws.InvalidUrl -> panic
    ws.OnOpen(socket) -> #(
      Model(..model, ws: Some(socket)),
      send_event(Some(socket), events.ClientConnected(model.player)),
    )
    ws.OnTextMessage(msg) -> {
      events.parse_event(msg)
      |> handle_app_event(model)
    }
    ws.OnBinaryMessage(_msg) -> #(model, effect.none())
    ws.OnClose(_reason) -> #(model, effect.none())
  }
}

fn handle_app_event(event: AppEvent, model: Model) -> #(Model, Effect(Msg)) {
  case event {
    events.UpdatedDiceState(dice_state) -> #(
      Model(..model, dice_state:),
      effect.none(),
    )
    events.ServerFoundPlayer(player) -> {
      io.println("server found player: " <> string.inspect(player))
      #(model, effect.none())
    }
    _ -> {
      io.println("unhandled event: " <> string.inspect(event))
      #(model, effect.none())
    }
  }
}

fn send_event(socket, event) {
  case socket {
    Some(s) -> ws.send(s, events.event_to_text(event))
    None -> {
      io.println("Socket not initiated")
      effect.none()
    }
  }
}

// Player
fn get_player_on_startup() -> Effect(Msg) {
  // use dispatch <- effect.from
  // get from localstorage
  let player_id =
    get_localstorage("qwixx")
    // parse to LocalData
    |> result.try(fn(string) {
      case json.parse(string, local_data_decoder()) {
        Ok(local_data) -> Ok(local_data.player_id)
        Error(err) -> {
          io.println(string.inspect(err))
          Error(Nil)
        }
      }
    })
    |> result.unwrap(uuid.nil)

  case player_id {
    id if id == uuid.nil -> {
      // post new id to server and save to local storage
      let new_id = uuid.v4()
      let body = shared_player.player_to_json(Player(new_id, None))
      let url = "/api/player"

      rsvp.post(
        url,
        body,
        rsvp.expect_json(shared_player.player_decoder(), ServerReturnedPlayer),
      )
    }
    id -> {
      // get player from server
      let url = "/api/player/" <> uuid.to_string(id)

      rsvp.get(
        url,
        rsvp.expect_json(shared_player.player_decoder(), ServerReturnedPlayer),
      )
    }
  }
}

fn update_player_name(model: Model) -> #(Model, Effect(Msg)) {
  let updated_player = Player(..model.player, name: Some(model.temp_name))
  let new_model = Model(..model, player: updated_player, temp_name: "")

  let url = "/api/player"
  let body = shared_player.player_to_json(updated_player)

  let effect =
    rsvp.put(
      url,
      body,
      rsvp.expect_json(shared_player.player_decoder(), ServerReturnedPlayer),
    )

  // Send updated name to server
  #(new_model, effect)
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
    <> shared_player.player_game_to_json(player_game) |> json.to_string(),
  )
  #(
    Model(..model, player_game:),
    send_event(model.ws, events.PlayerUpdatedPlayerGame(player_game)),
  )
}

// -----------------------------------------------
// View ------------------------------------------
// -----------------------------------------------

fn view(model: Model) -> Element(Msg) {
  case model.current_route {
    Start -> start_view(model)
    Lobby -> lobby_view(model)
    Game -> game_view(model)
  }
}

fn start_view(model: Model) -> Element(Msg) {
  let name = case model.player.name {
    Some(name) -> name
    None -> "Guest"
  }
  html.div([], [
    html.div([], [
      html.text("player name: " <> name),
    ]),
    html.div([], [
      html.input([
        attr.type_("text"),
        event.on_input(UserUpdatedName),
        attr.value(model.temp_name),
      ]),
      html.button(
        [
          event.on_click(UserSavedName),
        ],
        [html.text("Save")],
      ),
    ]),
    html.div([], [
      html.text("player id:"),
      html.text(uuid.to_string(model.player.id)),
    ]),
    html.div([], [
      html.text("Join an existing game:"),
      html.input([attr.type_("text")]),
    ]),
    html.div([], [
      html.text("Or start a new one:"),
      html.button([], [html.text("New Game")]),
    ]),
  ])
}

fn lobby_view(model: Model) -> Element(Msg) {
  html.div([], [html.text("Lobby Page!")])
}

fn game_view(model: Model) -> Element(Msg) {
  html.div([], [
    html.button([event.on_click(UserRolledDice)], [html.text("Roll Dice")]),
    dice_tray(model.dice_state),
    score_card(model.player_game),
  ])
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

// -----------------------------------------------
// Utils -----------------------------------------
// -----------------------------------------------

@external(javascript, "./client.ffi.mjs", "get_localstorage")
fn get_localstorage(_key: String) -> Result(String, Nil) {
  Error(Nil)
}

@external(javascript, "./client.ffi.mjs", "set_localstorage")
fn set_localstorage(_key: String, _value: String) -> Nil {
  Nil
}

type LocalData {
  LocalData(player_id: uuid.Uuid)
}

fn local_data_decoder() -> decode.Decoder(LocalData) {
  use player_id <- decode.field("player_id", decode.string)
  let assert Ok(uuid) = uuid.from_string(player_id)
  io.println("saved id: " <> uuid.to_string(uuid))
  decode.success(LocalData(player_id: uuid))
}

fn local_data_to_json(data: LocalData) -> json.Json {
  let LocalData(player_id:) = data

  json.object([#("player_id", json.string(uuid.to_string(player_id)))])
}

fn get_local_data() -> Effect(Msg) {
  use dispatch <- effect.from
  let result =
    result.try(get_localstorage("qwixx"), fn(string) {
      case json.parse(string, local_data_decoder()) {
        Ok(local_data) -> Ok(local_data)
        Error(_) -> Error(Nil)
      }
    })
  io.println("player result: " <> string.inspect(result))
  dispatch(LocalStorageGet(result))
}

fn save_local_data(data: LocalData) -> Effect(msg) {
  use _ <- effect.from
  let local_data_string = local_data_to_json(data) |> json.to_string()

  set_localstorage("qwixx", local_data_string)
}
