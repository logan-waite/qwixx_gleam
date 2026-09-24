import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/timestamp
import sqlight
import wisp
import youid/uuid.{type Uuid}

import server/parrot
import server/sql
import shared/player.{type Player, type PlayerGame, Player, PlayerGame} as app_player
import shared/utils

// Player

fn add_player_to_player(add_player: sql.AddPlayer) -> Player {
  let sql.AddPlayer(id:, name:) = add_player
  let assert Ok(player_id) = uuid.from_string(id)
  Player(id: player_id, name:)
}

pub fn create_player(player: Player, db_conn: sqlight.Connection) {
  let sql_result =
    uuid.to_string(player.id)
    |> sql.add_player(player.name)
    |> parrot.run_query(db_conn)

  case sql_result {
    Ok(row) -> {
      let maybe_player =
        row
        |> list.map(add_player_to_player)
        |> utils.unwrap_list()

      case maybe_player {
        Some(player) -> {
          let return_body =
            app_player.player_to_json(player) |> json.to_string()

          wisp.created()
          |> wisp.json_body(return_body)
        }
        None -> {
          // No row returned
          wisp.internal_server_error()
        }
      }
    }
    Error(err) -> {
      // db errors
      wisp.internal_server_error()
      |> wisp.json_body(string.inspect(err))
    }
  }
}

fn get_player_to_player(get_player: sql.GetPlayer) -> Player {
  let sql.GetPlayer(id:, name:) = get_player
  let assert Ok(player_id) = uuid.from_string(id)
  Player(id: player_id, name:)
}

pub fn get_player(id: String, db_conn: sqlight.Connection) {
  let sql_result =
    sql.get_player(id)
    |> parrot.run_query(db_conn)

  case sql_result {
    Ok(row) -> {
      let maybe_player =
        row
        |> list.map(get_player_to_player)
        |> utils.unwrap_list()

      case maybe_player {
        Some(player) -> {
          let return_body =
            app_player.player_to_json(player) |> json.to_string()

          wisp.ok()
          |> wisp.json_body(return_body)
        }
        None -> {
          // No row returned
          wisp.internal_server_error()
        }
      }
    }
    Error(err) -> {
      // db errors
      wisp.internal_server_error()
      |> wisp.json_body(string.inspect(err))
    }
  }
}

fn update_player_to_player(update_player: sql.UpdatePlayer) -> Player {
  let sql.UpdatePlayer(id:, name:) = update_player
  let assert Ok(player_id) = uuid.from_string(id)
  Player(id: player_id, name:)
}

pub fn update_player(player: Player, db_conn: sqlight.Connection) {
  let player_id = uuid.to_string(player.id)
  let sql_result =
    sql.update_player(id: player_id, name: player.name)
    |> parrot.run_query(db_conn)

  case sql_result {
    Ok(row) -> {
      let maybe_player =
        row
        |> list.map(update_player_to_player)
        |> utils.unwrap_list()

      case maybe_player {
        Some(player) -> {
          let return_body =
            app_player.player_to_json(player) |> json.to_string()

          wisp.ok()
          |> wisp.json_body(return_body)
        }
        None -> {
          // No row returned
          io.println("no row returned")
          wisp.internal_server_error()
        }
      }
    }
    Error(err) -> {
      // db errors
      wisp.internal_server_error()
      |> wisp.json_body(string.inspect(err))
    }
  }
}

// player game

fn add_player_game_to_player_game(add_player_game: sql.AddPlayerGame) {
  let sql.AddPlayerGame(
    id:,
    player_id:,
    game_id:,
    joined:,
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
  ) = add_player_game

  let id = id |> uuid.from_string() |> result.unwrap(uuid.nil)
  let player_id = player_id |> uuid.from_string() |> result.unwrap(uuid.nil)
  let game_id =
    game_id
    |> uuid.from_string()
    |> result.unwrap(uuid.nil)
  let joined =
    timestamp.from_unix_seconds_and_nanoseconds(
      joined / 1_000_000_000,
      joined % 1_000_000_000,
    )
  // let joined = joined |>   

  PlayerGame(
    id:,
    player_id:,
    game_id:,
    joined:,
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
  )
}

pub fn create_player_game(
  player_id: Uuid,
  game_id: Uuid,
  db_conn: sqlight.Connection,
) {
  let joined =
    timestamp.system_time()
    |> timestamp.to_unix_seconds_and_nanoseconds()
    |> fn(time) {
      let #(seconds, nanoseconds) = time
      seconds * 1_000_000_000 + nanoseconds
    }

  let sql_result =
    sql.add_player_game(
      id: uuid.v4() |> uuid.to_string(),
      player_id: player_id |> uuid.to_string(),
      game_id: game_id |> uuid.to_string,
      joined: joined,
      ready: True,
      red: 0,
      yellow: 0,
      green: 0,
      blue: 0,
      missed: 0,
    )
  case parrot.run_query(sql_result, db_conn) {
    Ok(row) -> {
      let maybe_player_game =
        row |> list.map(add_player_game_to_player_game) |> utils.unwrap_list()

      case maybe_player_game {
        Some(player_game) -> {
          let return_body =
            player_game |> app_player.player_game_to_json() |> json.to_string()
          wisp.created()
          |> wisp.json_body(return_body)
        }
        None -> {
          io.println("no row returned")
          wisp.internal_server_error()
        }
      }
    }
    Error(err) -> {
      wisp.internal_server_error()
      |> wisp.json_body(string.inspect(err))
    }
  }
}

fn get_player_game_to_player_game(
  get_player_game: sql.GetPlayerGame,
) -> PlayerGame {
  let sql.GetPlayerGame(
    id:,
    player_id:,
    game_id:,
    joined:,
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
  ) = get_player_game

  let id = id |> uuid.from_string() |> result.unwrap(uuid.nil)
  let player_id = player_id |> uuid.from_string() |> result.unwrap(uuid.nil)
  let game_id =
    game_id
    |> uuid.from_string()
    |> result.unwrap(uuid.nil)
  let joined =
    timestamp.from_unix_seconds_and_nanoseconds(
      joined / 1_000_000_000,
      joined % 1_000_000_000,
    )
  // let joined = joined |>   

  PlayerGame(
    id:,
    player_id:,
    game_id:,
    joined:,
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
  )
}

pub fn get_player_game(
  player_id: String,
  game_code: String,
  db_conn: sqlight.Connection,
) {
  let sql_result = sql.get_player_game(player_id, game_code)
  case parrot.run_query(sql_result, db_conn) {
    Ok(row) -> {
      let maybe_player_game =
        row |> list.map(get_player_game_to_player_game) |> utils.unwrap_list()
      case maybe_player_game {
        Some(player_game) -> {
          let return_body =
            player_game |> app_player.player_game_to_json() |> json.to_string()
          wisp.ok()
          |> wisp.json_body(return_body)
        }
        None -> {
          wisp.not_found()
        }
      }
    }
    Error(err) -> {
      wisp.internal_server_error()
      |> wisp.json_body(string.inspect(err))
    }
  }
}
