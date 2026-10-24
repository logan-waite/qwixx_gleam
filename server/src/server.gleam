import gleam/erlang/process
import gleam/otp/factory_supervisor as factory
import gleam/otp/static_supervisor

import server/room
import server/room_manager
import server/web_server

pub fn main() -> Nil {
  let room_factory_name = process.new_name("room_factory")
  let room_manager_name = process.new_name("room_manager")

  let room_factory =
    factory.worker_child(room.start)
    |> factory.named(room_factory_name)
    |> factory.supervised

  let assert Ok(_supervisor) =
    static_supervisor.new(static_supervisor.OneForOne)
    |> static_supervisor.add(room_factory)
    |> static_supervisor.add(room_manager.supervised(
      room_manager_name,
      room_factory_name,
    ))
    |> static_supervisor.add(web_server.supervised(room_manager_name))
    |> static_supervisor.start

  process.sleep_forever()
}
