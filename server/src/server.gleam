import dot_env
import dot_env/env
import gleam/erlang/process
import mist
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
    _, _ -> wisp.not_found()
  }
}
// DATABASE SETUP ---------------------------------------------
