import dot_env
import dot_env/env
import gleam/dynamic/decode
import gleam/erlang/process
import gleam/http.{Get, Post}
import gleam/http/request.{type Request as BaseRequest}
import gleam/http/response.{type Response as BaseResponse}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
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

import server/db_utils
import server/parrot
import server/sql
import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type AppEvent}
import shared/player.{type Player, type PlayerGame} as shared_player

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
  let player = shared_player.new_player()
  let player_game = shared_player.new_player_game(player.id, uuid.v4())
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

      case decode.run(json, shared_player.player_decoder()) {
        Ok(player_req) -> {
          let sql_player =
            sql.add_player(uuid.to_string(player_req.id), player_req.name)
            |> parrot.run_query(db_conn)
            |> list.first()
          // Adding a player should always return 1 item

          case sql_player {
            Ok(sql_player) -> {
              let player =
                db_utils.sql_player_to_player(db_utils.Add(sql_player))
              wisp.json_response(
                shared_player.player_to_json(player) |> json.to_string(),
                200,
              )
            }
            Error(_err) -> wisp.internal_server_error()
          }
        }
        Error(err) -> wisp.bad_request(string.inspect(err))
      }
    }
    Get, ["player", id] -> {
      let maybe_player =
        sql.get_player(id)
        |> parrot.run_query(db_conn)
        |> list.map(db_utils.Get)
        |> list.map(db_utils.sql_player_to_player)
        |> array_to_option()

      case maybe_player {
        Some(player) -> {
          wisp.json_response(
            json.to_string(shared_player.player_to_json(player)),
            200,
          )
        }
        None -> {
          wisp.not_found()
        }
      }
    }
    _, _ -> wisp.not_found()
  }
}

fn array_to_option(list: List(t)) -> Option(t) {
  case list {
    [] -> None
    [item] -> Some(item)
    _ -> panic as "Can't turn a list with multiple elements into an Option"
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

fn get_player(
  player_id: String,
  db_conn: sqlight.Connection,
) -> Option(Player) {
  let rows = sql.get_player(player_id) |> parrot.run_query(db_conn)
  case rows {
    [] -> None
    [db_player] -> Some(db_utils.sql_player_to_player(db_utils.Get(db_player)))
    _ -> None
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
    // events.ClientConnected(updated_player) -> {
    //   let player_id = uuid.to_string(updated_player.id)
    //   let player = get_player(state.db_conn, player_id)
    //   case player {
    //     Some(player) -> #(
    //       Some(events.ServerFoundPlayer(player)),
    //       WebSocketState(..state, player:),
    //     )
    //     None -> {
    //       let rows =
    //         sql.add_player(player_id, updated_player.name)
    //         |> parrot.run_query(state.db_conn)
    //       case rows {
    //         [db_player] -> {
    //           #(
    //             None,
    //             WebSocketState(
    //               ..state,
    //               player: db_utils.sql_player_to_player(db_utils.Add(db_player)),
    //             ),
    //           )
    //         }
    //         _ -> #(None, state)
    //       }
    //     }
    //   }
    // }
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
