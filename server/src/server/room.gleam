import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/otp/actor
import gleam/string
import youid/uuid.{type Uuid}

import shared/events as app_events
import shared/game.{type Game, type GameCode, Game} as app_game
import shared/player.{type Player, type PlayerGame} as app_player

pub fn start(game: Game) {
  actor.new(GameRoom(
    player_games: dict.new(),
    subjects: dict.new(),
    state: game,
  ))
  |> actor.on_message(handle_message)
  |> actor.start
}

pub type GameRoom {
  GameRoom(
    player_games: Dict(Uuid, PlayerGame),
    subjects: Dict(Uuid, Subject(Message)),
    state: Game,
  )
}

pub type Message {
  // join/leave with game code
  Join(PlayerGame, Subject(Message))
  Leave(PlayerGame)
  PlayerUpdated(PlayerGame)
  Broadcast(app_events.AppEvent)
  GameEnded
}

fn handle_message(game: GameRoom, message: Message) {
  case message {
    Join(player_game, subject) -> {
      let player_games =
        dict.insert(game.player_games, player_game.id, player_game)
      let subjects = dict.insert(game.subjects, player_game.id, subject)
      let game = GameRoom(..game, player_games:, subjects:)
      // broadcast to every connection that a player joined
      broadcast(
        app_events.UpdatePlayerList(dict.values(player_games)),
        subjects,
      )

      actor.continue(game)
    }
    Leave(player_game) -> {
      let player_games = dict.delete(game.player_games, player_game.id)
      let subjects = dict.delete(game.subjects, player_game.id)
      let game = GameRoom(..game, player_games:, subjects:)
      // broadcast to every remaining connection that a player left
      actor.continue(game)
    }
    PlayerUpdated(player_game) -> {
      let player_games =
        dict.upsert(game.player_games, player_game.id, fn(_existing) {
          player_game
        })
      let game = GameRoom(..game, player_games:)
      //broadcast
      broadcast(
        app_events.UpdatePlayerList(dict.values(player_games)),
        game.subjects,
      )
      actor.continue(game)
    }
    Broadcast(event) -> {
      io.println("got a broadcast event")
      todo
    }
    GameEnded -> actor.stop()
  }
}

pub fn broadcast(
  message: app_events.AppEvent,
  subjects: Dict(Uuid, Subject(Message)),
) {
  dict.each(subjects, fn(_k, subject) {
    process.send(subject, Broadcast(message))
  })
}
