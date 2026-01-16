import dot_env
import dot_env/env
import gleam/erlang/process
import gleam/http.{Get}
import gleam/int
import gleam/json
import lustre/attribute
import lustre/element
import lustre/element/html
import mist
import shared/dice.{type DiceState, DiceState, Die}
import wisp.{type Request, type Response}
import wisp/wisp_mist

pub fn main() -> Nil {
  wisp.configure_logger()

  dot_env.new()
  |> dot_env.set_path(".env")
  |> dot_env.set_debug(False)
  |> dot_env.load()

  let assert Ok(secret_key_base) = env.get_string("SECRET_KEY")

  // set up database
  let db = Nil

  let assert Ok(priv_directory) = wisp.priv_directory("server")
  let static_directory = priv_directory <> "/static"

  let assert Ok(_) =
    handle_request(db, static_directory, _)
    |> wisp_mist.handler(secret_key_base)
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

fn handle_request(_: Nil, static_directory: String, req: Request) -> Response {
  use req <- app_middleware(req, static_directory)

  case req.method, wisp.path_segments(req) {
    Get, ["api", "roll-dice"] -> handle_roll_dice()
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

  html
  |> element.to_document_string
  |> wisp.html_response(200)
}

fn handle_roll_dice() -> Response {
  let dice_state =
    roll_dice()
    |> dice.dice_state_to_json()
    |> json.to_string_tree()

  wisp.response(200)
  |> wisp.string_tree_body(dice_state)
  |> wisp.set_header("content-type", "application/json")
}

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
