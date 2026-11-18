import gleam/dict.{type Dict}
import gleam/erlang/process.{type Subject}
import gleam/io
import gleam/option.{None, Some}
import gleam/otp/actor
import gleam/result
import gleam/string
import server/database/db
import sqlight
import youid/uuid.{type Uuid}

import shared/events as app_events
import shared/game.{type Game, Game} as app_game
import shared/player.{type PlayerGame, Player, PlayerGame}

pub fn start(start_args: #(Game, sqlight.Connection)) {
  let #(game, db_conn) = start_args
  actor.new(GameRoom(
    db_conn:,
    player_games: dict.new(),
    subjects: dict.new(),
    state: game,
  ))
  |> actor.on_message(handle_message)
  |> actor.start
}

pub type GameRoom {
  GameRoom(
    db_conn: sqlight.Connection,
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
  StartGame
  Broadcast(app_events.AppEvent)
  GameEnded
}

fn handle_message(game_room: GameRoom, message: Message) {
  case message {
    Join(player_game, subject) -> {
      let player_games =
        dict.insert(game_room.player_games, player_game.id, player_game)
      let subjects = dict.insert(game_room.subjects, player_game.id, subject)
      let game = GameRoom(..game_room, player_games:, subjects:)
      // broadcast to every connection that a player joined
      broadcast(
        app_events.UpdatePlayerList(dict.values(player_games)),
        subjects,
      )

      actor.continue(game)
    }
    Leave(player_game) -> {
      let player_games = dict.delete(game_room.player_games, player_game.id)
      let subjects = dict.delete(game_room.subjects, player_game.id)
      let game = GameRoom(..game_room, player_games:, subjects:)
      // broadcast to every remaining connection that a player left
      actor.continue(game)
    }
    PlayerUpdated(player_game) -> {
      // update db first
      let player_update = case
        game_room.player_games |> dict.get(player_game.id)
      {
        Ok(player_to_update) -> {
          let player = Player(name: player_game.name, id: player_game.player_id)
          case player_to_update {
            p if p.name != player_game.name -> {
              db.update_player(player, game_room.db_conn)
            }
            _ -> {
              Ok(Some(player))
            }
          }
        }
        Error(err) -> {
          Error("error getting player from state: " <> string.inspect(err))
        }
      }

      let player_game_update =
        db.update_player_game(player_game, game_room.db_conn)

      let db_results = player_update |> result.try(fn(_) { player_game_update })

      case db_results {
        Ok(_player_game) -> {
          let player_games =
            dict.upsert(game_room.player_games, player_game.id, fn(_existing) {
              player_game
            })
          let game = GameRoom(..game_room, player_games:)
          //broadcast
          broadcast(
            app_events.UpdatePlayerList(dict.values(player_games)),
            game.subjects,
          )
          actor.continue(game)
        }
        Error(err) -> {
          io.println("error saving to db: " <> err)
          actor.continue(game_room)
        }
      }
    }
    StartGame -> {
      // To start a game:
      // set game status to "in progress"
      // set all player ready to False (db and local state)

      let db_result =
        db.update_game(
          app_game.InProgress,
          game_room.state.code,
          game_room.db_conn,
        )
        |> result.try(fn(maybe_game) {
          option.to_result(maybe_game, "No game found to update")
        })
        |> result.try(fn(_) {
          db.update_game_player_ready(
            False,
            game_room.state.code,
            game_room.db_conn,
          )
        })

      case db_result {
        Ok(_) -> {
          let player_games =
            dict.map_values(game_room.player_games, fn(_id, player_game) {
              PlayerGame(..player_game, ready: False)
            })
          let updated_state =
            Game(..game_room.state, status: app_game.InProgress)
          let updated_game =
            GameRoom(..game_room, player_games:, state: updated_state)
          // broadcast the game is ready to start
          broadcast(
            app_events.UpdatePlayerList(dict.values(player_games)),
            game_room.subjects,
          )
          broadcast(app_events.GameStarted(game_room.state), game_room.subjects)
          actor.continue(updated_game)
        }
        Error(err) -> {
          io.println("error saving to db: " <> err)
          actor.continue(game_room)
        }
      }
    }
    Broadcast(event) -> {
      todo as "Don't know what to do with a Broadcast event"
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
