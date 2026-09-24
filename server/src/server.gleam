import dot_env
import dot_env/env
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http.{Get, Post, Put}
import gleam/http/request.{type Request as BaseRequest}
import gleam/http/response.{type Response as BaseResponse}
import gleam/int
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute
import lustre/element
import lustre/element/html
import mist.{type Connection, type ResponseData}
import sqlight
import wisp.{type Request, type Response}
import wisp/wisp_mist
import youid/uuid

import server/game_service
import server/player_service
import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type AppEvent}
import shared/game as app_game
import shared/player.{type Player, type PlayerGame} as app_player

pub fn main() -> Nil {
  wisp.configure_logger()

  dot_env.new()
  |> dot_env.set_path(".env")
  |> dot_env.set_debug(False)
  |> dot_env.load()

  let assert Ok(secret_key_base) = env.get_string("SECRET_KEY")

  // set up database
  use db_conn <- sqlight.with_connection("file:database.db")

  // initial websocket state (will come from db eventually)
  let player = app_player.new_player()
  let player_game = app_player.new_player_game(player.id, uuid.v4())
  let ws_state = WebSocketState(db_conn:, player:, player_game:)

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let assert Ok(_) =
    fn(req: BaseRequest(Connection)) -> BaseResponse(ResponseData) {
      case request.path_segments(req) {
        ["ws"] ->
          mist.websocket(
            request: req,
            on_init: fn(conn) {
              let _ =
                mist.send_text_frame(
                  conn,
                  events.event_to_text(events.ServerConnected),
                )
              #(ws_state, None)
            },
            on_close: fn(_state) { io.println("closing ws connection") },
            handler: handle_ws_request,
          )
        _ ->
          handle_request(db_conn, static_directory, _)
          |> wisp_mist.handler(secret_key_base)
          |> fn(fun) { fun(req) }
      }
    }
    |> mist.new
    |> mist.port(3000)
    |> mist.start

  process.sleep_forever()
}

// REQUEST HANDLERS -------------------------------------------
fn app_middleware(
  req: Request,
  static_directory: String,
  next: fn(Request) -> Response,
) -> Response {
  let req = wisp.method_override(req)
  use <- wisp.log_request(req)
  use <- wisp.rescue_crashes
  use req <- wisp.handle_head(req)
  use <- wisp.serve_static(req, under: "/static", from: static_directory)

  next(req)
}

// Api
fn handle_request(
  db_conn: sqlight.Connection,
  static_directory: String,
  req: Request,
) -> Response {
  use req <- app_middleware(req, static_directory)

  case req.method, wisp.path_segments(req) {
    _, ["api", ..rest] -> handle_api_request(db_conn, req, rest)
    Get, _ -> serve_index()
    _, _ -> wisp.not_found()
  }
}

fn serve_index() {
  let html =
    html.html([], [
      html.head([], [
        html.title([], "Qwixx"),
        html.script(
          [attribute.type_("module"), attribute.src("/static/client.js")],
          "",
        ),
      ]),
      html.body([], [html.div([attribute.id("app")], [])]),
    ])

  wisp.html_response(html |> element.to_document_string, 200)
}

// Api Endpoints
fn handle_api_request(db_conn, req: Request, path: List(String)) {
  case req.method, path {
    Post, ["player"] -> {
      use json <- wisp.require_json(req)

      case decode.run(json, app_player.player_decoder()) {
        Ok(player_req) -> player_service.create_player(player_req, db_conn)
        Error(err) -> wisp.bad_request(string.inspect(err))
      }
    }
    Get, ["player", id] -> {
      player_service.get_player(id, db_conn)
    }
    Put, ["player"] -> {
      use json <- wisp.require_json(req)

      case decode.run(json, app_player.player_decoder()) {
        Ok(player) -> player_service.update_player(player, db_conn)
        Error(err) -> wisp.bad_request(string.inspect(err))
      }
    }
    Post, ["game"] -> {
      use json <- wisp.require_json(req)

      case decode.run(json, app_player.player_decoder()) {
        Ok(player) -> {
          let game = game_service.create_game(db_conn)
          let player_game =
            player_service.create_player_game(player.id, game.id, db_conn)
          let body = app_game.game_to_json(game) |> json.to_string()

          wisp.created()
          |> wisp.json_body(body)
        }
        Error(err) -> {
          wisp.bad_request(string.inspect(err))
        }
      }
    }
    Get, ["game", code] -> game_service.get_game_by_code(code, db_conn)
    Post, ["player-game"] -> {
      todo
    }
    Get, ["game", game_code, "player", player_id] ->
      player_service.get_player_game(player_id, game_code, db_conn)
    _, _ -> wisp.not_found()
  }
}

type WebSocketState {
  WebSocketState(
    db_conn: sqlight.Connection,
    player: Player,
    player_game: PlayerGame,
  )
}

// websockets
fn handle_ws_request(state, message: mist.WebsocketMessage(a), conn) {
  case message {
    mist.Text(msg) -> {
      let event = events.parse_event(msg)
      let #(response, new_state) = handle_app_event(event, state)
      case response {
        Some(new_event) -> {
          let _ =
            events.event_to_text(new_event) |> mist.send_text_frame(conn, _)
          mist.continue(new_state)
        }
        None -> mist.continue(new_state)
      }
    }
    mist.Custom(_msg) -> {
      // io.println("Received custom msg: " <> msg)
      io.println("Received custom msg: ")
      mist.continue(state)
    }
    mist.Binary(_bit_array) -> {
      io.println("Whatchu doin'?")
      mist.continue(state)
    }
    mist.Closed | mist.Shutdown -> mist.stop()
  }
}

fn handle_app_event(
  event: AppEvent,
  state,
) -> #(Option(AppEvent), WebSocketState) {
  case event {
    events.RollDice -> #(
      Some(
        roll_dice()
        |> events.UpdatedDiceState,
      ),
      state,
    )
    events.PlayerUpdatedPlayerGame(updated_player_game) -> #(
      Some(events.NoOp),
      WebSocketState(..state, player_game: updated_player_game),
    )
    _ -> #(None, state)
  }
}

// Business Logic
fn roll_dice() -> DiceState {
  let red = Die(locked: False, value: int.random(6) + 1)
  let yellow = Die(locked: False, value: int.random(6) + 1)
  let blue = Die(locked: False, value: int.random(6) + 1)
  let green = Die(locked: False, value: int.random(6) + 1)
  let white_1 = Die(locked: False, value: int.random(6) + 1)
  let white_2 = Die(locked: False, value: int.random(6) + 1)
  DiceState(red:, yellow:, blue:, green:, white_1:, white_2:)
}
// DATABASE SETUP ---------------------------------------------
