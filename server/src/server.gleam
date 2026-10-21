import gleam/erlang/process
import gleam/otp/static_supervisor
import server/web_server

pub fn main() -> Nil {
  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(web_server.supervised())
    |> static_supervisor.start

  process.sleep_forever()
}
