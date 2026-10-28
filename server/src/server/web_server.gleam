import dot_env
import dot_env/env
import gleam/dynamic/decode
import gleam/erlang/process.{type Subject}
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
import server/room
import server/room_manager
import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type AppEvent}
import shared/game as app_game
import shared/player.{type Player, type PlayerGame, Player} as app_player

pub fn supervised(room_manager_name: process.Name(room_manager.Message)) {
  wisp.configure_logger()

  dot_env.new()
  |> dot_env.set_path(".env")
  |> dot_env.set_debug(False)
  |> dot_env.load()

  let assert Ok(secret_key_base) = env.get_string("SECRET_KEY")

  // set up database
  // use db_conn <- sqlight.with_connection("file:database.db")
  let db_conn = case sqlight.open("file:database.db") {
    Ok(conn) -> conn
    Error(err) -> {
      let panic_message = "Couldn't open database: " <> string.inspect(err)
      panic as panic_message
    }
  }

  // initial websocket state (will come from db eventually)
  // let player = app_player.new_player()
  // let player_game = app_player.new_player_game(player.id, uuid.v4())
  let manager = process.named_subject(room_manager_name)
  let ws_state = WebSocketState(db_conn, None, manager)

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  fn(req: BaseRequest(Connection)) -> BaseResponse(ResponseData) {
    case request.path_segments(req) {
      ["ws"] ->
        mist.websocket(
          request: req,
          on_init: fn(_conn) {
            let outgoing = process.new_subject()
            let selector = process.new_selector() |> process.select(outgoing)

            let ws_state = WebSocketState(..ws_state, subject: Some(outgoing))
            // let _ =
            //   mist.send_text_frame(
            //     conn,
            //     events.event_to_text(events.ServerConnected),
            //   )
            io.println(
              "on_init return value: "
              <> string.inspect(#(ws_state, Some(selector))),
            )
            #(ws_state, Some(selector))
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
  |> mist.supervised
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
    Get, ["player", id] -> player_service.get_player(id, db_conn)
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
          let _player_game =
            player_service.create_player_game(player, game, db_conn)
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
    Post, ["game", game_code, "player"] -> {
      use json <- wisp.require_json(req)

      case
        decode.run(json, player_service.create_player_game_request_decoder())
      {
        Ok(create_player_game_request) -> {
          let player_service.CreatePlayerGameRequest(player_id:) =
            create_player_game_request
          case
            player_service.get_player_db(uuid.to_string(player_id), db_conn)
          {
            Some(player) -> {
              case game_service.get_game_by_code_db(game_code, db_conn) {
                Some(game) -> {
                  let response =
                    player_service.create_player_game(player, game, db_conn)
                  // let player_games = player_service.get_game_players()
                  // events.UpdatePlayerList(player_games)
                  // |> events.event_to_text()
                  // |> mist.send_text_frame(conn, _)
                  response
                }
                None -> {
                  wisp.not_found()
                }
              }
            }

            None -> {
              wisp.not_found()
            }
          }
        }
        Error(_) -> {
          todo
        }
      }
    }
    Get, ["game", game_code, "player", player_id] ->
      player_service.get_player_game(player_id, game_code, db_conn)
    _, _ -> {
      io.println("unknown route called")
      wisp.not_found()
    }
  }
}

type WebSocketState {
  WebSocketState(
    db_conn: sqlight.Connection,
    subject: Option(Subject(room.Message)),
    room_manager: Subject(room_manager.Message),
  )
}

// websockets
fn handle_ws_request(
  state,
  message: mist.WebsocketMessage(room.Message),
  conn,
) {
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
    mist.Custom(msg) -> {
      io.println("Received custom msg: " <> string.inspect(msg))
      case msg {
        room.Broadcast(event) -> {
          let _ = events.event_to_text(event) |> mist.send_text_frame(conn, _)
          mist.continue(state)
        }
        _ -> {
          io.println("haven't implemented this room message yet")
          mist.continue(state)
        }
      }
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
  state: WebSocketState,
) -> #(Option(AppEvent), WebSocketState) {
  case event {
    events.JoinGame(game, player_game) -> {
      // now we join the game room using the subject in the state

      let subject = case state.subject {
        Some(sub) -> sub
        None -> panic as "We need a subject from on_init to send messages to!"
      }

      case room_manager.get_or_start_room(state.room_manager, game) {
        Ok(room_subject) -> {
          io.println("got room subject: " <> string.inspect(room_subject))
          process.send(room_subject, room.Join(player_game, subject))
        }
        Error(Nil) -> {
          io.println("got an error from getting room")
        }
      }
      // process.send(subject, .Join(player, subject))
      #(None, state)
    }
    events.UpdatePlayerGame(player_game) -> {
      // Update database
      let player = Player(name: player_game.name, id: player_game.player_id)
      case player_service.update_player_db(player, state.db_conn) {
        Some(_player) -> {
          //notify room
          case
            room_manager.get_room(state.room_manager, player_game.game_code)
          {
            Ok(room_subject) -> {
              process.send(room_subject, room.PlayerUpdated(player_game))
            }
            Error(Nil) -> {
              io.println("no room to get, need to reconnect")
              todo
            }
          }
        }
        None -> todo
      }
      #(None, state)
    }
    events.RollDice -> #(
      Some(
        roll_dice()
        |> events.UpdatedDiceState,
      ),
      state,
    )
    events.PlayerUpdatedPlayerGame(updated_player_game) -> #(
      Some(events.NoOp),
      state,
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
