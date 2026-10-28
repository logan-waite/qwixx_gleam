import gleam/dict.{type Dict}
import gleam/erlang/process.{type Name, type Subject}
import gleam/io
import gleam/otp/actor
import gleam/otp/factory_supervisor
import gleam/otp/supervision

import server/room
import shared/game.{type Game, type GameCode}

pub type Message {
  GetOrStartRoom(
    game: Game,
    reply_to: Subject(Result(Subject(room.Message), Nil)),
  )
  GetRoom(code: GameCode, reply_to: Subject(Result(Subject(room.Message), Nil)))
}

pub type State {
  State(
    rooms: Dict(GameCode, Subject(room.Message)),
    factory_name: Name(factory_supervisor.Message(Game, Subject(room.Message))),
  )
}

pub fn supervised(
  manager_name: Name(Message),
  factory_name: Name(factory_supervisor.Message(Game, Subject(room.Message))),
) {
  supervision.worker(fn() { start(manager_name, factory_name) })
}

pub fn start(
  manager_name: Name(Message),
  factory_name: Name(factory_supervisor.Message(Game, Subject(room.Message))),
) -> actor.StartResult(Subject(Message)) {
  actor.new(State(rooms: dict.new(), factory_name:))
  |> actor.named(manager_name)
  |> actor.on_message(handle_message)
  |> actor.start
}

pub fn get_or_start_room(
  manager: Subject(Message),
  game: Game,
) -> Result(Subject(room.Message), Nil) {
  process.call(manager, 5000, GetOrStartRoom(game, _))
}

pub fn get_room(
  manager: Subject(Message),
  code: GameCode,
) -> Result(Subject(room.Message), Nil) {
  process.call(manager, 5000, GetRoom(code, _))
}

fn handle_message(state: State, message: Message) {
  case message {
    GetOrStartRoom(game, reply_to) -> {
      case dict.get(state.rooms, game.code) {
        Ok(room_subject) -> {
          process.send(reply_to, Ok(room_subject))
          actor.continue(state)
        }
        Error(Nil) -> {
          let factory = factory_supervisor.get_by_name(state.factory_name)

          case factory_supervisor.start_child(factory, game) {
            Ok(started) -> {
              let room_subject = started.data

              let rooms = dict.insert(state.rooms, game.code, room_subject)

              process.send(reply_to, Ok(room_subject))

              actor.continue(State(..state, rooms:))
            }
            Error(_) -> {
              process.send(reply_to, Error(Nil))
              actor.continue(state)
            }
          }
        }
      }
    }
    GetRoom(code, reply_to) -> {
      case dict.get(state.rooms, code) {
        Ok(room_subject) -> {
          process.send(reply_to, Ok(room_subject))
          actor.continue(state)
        }
        Error(Nil) -> {
          process.send(reply_to, Error(Nil))
          actor.continue(state)
        }
      }
    }
  }
}
