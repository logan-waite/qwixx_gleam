import dot_env
import dot_env/env
import gleam/erlang/process
import gleam/http.{Get}
import gleam/http/request.{type Request as BaseRequest}
import gleam/http/response.{type Response as BaseResponse}
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{None}
import lustre/attribute
import lustre/element
import lustre/element/html
import mist.{type Connection, type ResponseData}
import wisp.{type Request, type Response}
import wisp/wisp_mist
import youid/uuid

import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type AppEvent}
import shared/player.{type Player, Player, ScoreCard}

pub fn main() -> Nil {
  wisp.configure_logger()

  dot_env.new()
  |> dot_env.set_path(".env")
  |> dot_env.set_debug(False)
  |> dot_env.load()

  let assert Ok(secret_key_base) = env.get_string("SECRET_KEY")

  // set up database
  let db = Nil

  // initial player state (will come from db eventually
  let player = player.new_player()

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let assert Ok(_) =
    fn(req: BaseRequest(Connection)) -> BaseResponse(ResponseData) {
      case request.path_segments(req) {
        ["ws"] ->
          mist.websocket(
            request: req,
            on_init: fn(conn) {
              mist.send_text_frame(
                conn,
                events.event_to_text(events.SocketConnected(player)),
              )
              #(player, None)
            },
            on_close: fn(_state) { io.println("closing ws connection") },
            handler: handle_ws_request,
          )
        _ ->
          handle_request(db, static_directory, _)
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
fn handle_request(_: Nil, static_directory: String, req: Request) -> Response {
  use req <- app_middleware(req, static_directory)

  case req.method, wisp.path_segments(req) {
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

// websockets
fn handle_ws_request(state, message: mist.WebsocketMessage(a), conn) {
  case message {
    mist.Text(msg) -> {
      let event = events.parse_event(msg)
      let #(response, new_state) = handle_app_event(event, state)
      events.event_to_text(response) |> mist.send_text_frame(conn, _)
      io.println(
        "updated state: "
        <> player.player_to_json(new_state) |> json.to_string(),
      )
      mist.continue(new_state)
    }
    mist.Custom(msg) -> {
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

fn handle_app_event(event: AppEvent, state) -> #(AppEvent, Player) {
  case event {
    events.RollDice -> #(
      roll_dice()
        |> events.UpdatedDiceState,
      state,
    )
    events.PlayerUpdatedScoreCard(updated_player) -> #(
      events.NoOp,
      Player(..state, score_card: updated_player.score_card),
    )

    _ -> #(events.NoOp, state)
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
