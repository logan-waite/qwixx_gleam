import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/otp/actor
import gleam/string
import youid/uuid.{type Uuid}

import shared/events as app_event
import shared/game.{type Game, type GameCode, Game} as app_game
import shared/player.{type PlayerGame} as app_player

pub fn start(game: Game) {
  actor.new(GameRoom(players: dict.new(), subjects: dict.new(), state: game))
  |> actor.on_message(handle_message)
  |> actor.start
}

pub type GameRoom {
  GameRoom(
    players: Dict(Uuid, PlayerGame),
    subjects: Dict(Uuid, Subject(Message)),
    state: Game,
  )
}

pub type Message {
  // join/leave with game code
  Join(PlayerGame, Subject(Message))
  Leave(PlayerGame)
  // PlayerUpdated(Player)
  Broadcast(app_event.AppEvent)
  GameEnded
}

fn handle_message(game: GameRoom, message: Message) {
  io.println("handling gameroom message")
  case message {
    Join(player, subject) -> {
      let players = dict.insert(game.players, player.id, player)
      let subjects = dict.insert(game.subjects, player.id, subject)
      let game = GameRoom(..game, players:, subjects:)
      // broadcast to every connection that a player joined
      broadcast(app_event.UpdatePlayerList(dict.values(players)), subjects)

      actor.continue(game)
    }
    Leave(player) -> {
      let players = dict.delete(game.players, player.id)
      let subjects = dict.delete(game.subjects, player.id)
      let game = GameRoom(..game, players:, subjects:)
      // broadcast to every remaining connection that a player left
      actor.continue(game)
    }
    // PlayerUpdated(player) -> {
    //   let players =
    //     dict.upsert(game.players, player.id, fn(_existing) { player })
    //   let game = GameRoom(..game, players:)
    //   //broadcast
    //   actor.continue(game)
    // }
    Broadcast(event) -> {
      todo
    }
    GameEnded -> actor.stop()
  }
}

pub fn broadcast(
  message: app_event.AppEvent,
  subjects: Dict(Uuid, Subject(Message)),
) {
  dict.each(subjects, fn(_k, subject) {
    process.send(subject, Broadcast(message))
  })
}
