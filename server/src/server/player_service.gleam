import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import sqlight
import wisp
import youid/uuid.{type Uuid}

import server/parrot
import server/sql
import shared/player.{type Player, Player} as app_player

fn array_to_option(list: List(t)) -> Option(t) {
  case list {
    [] -> None
    [item] -> Some(item)
    _ -> panic as "Can't turn a list with multiple elements into an Option"
  }
}

fn add_player_to_player(add_player: sql.AddPlayer) -> Player {
  let sql.AddPlayer(id:, name:) = add_player
  let assert Ok(player_id) = uuid.from_string(id)
  Player(id: player_id, name:)
}

fn get_player_to_player(get_player: sql.GetPlayer) -> Player {
  let sql.GetPlayer(id:, name:) = get_player
  let assert Ok(player_id) = uuid.from_string(id)
  Player(id: player_id, name:)
}

fn update_player_to_player(update_player: sql.UpdatePlayer) -> Player {
  let sql.UpdatePlayer(id:, name:) = update_player
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
        |> array_to_option()

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

pub fn get_player(id: String, db_conn: sqlight.Connection) {
  let sql_result =
    sql.get_player(id)
    |> parrot.run_query(db_conn)

  case sql_result {
    Ok(row) -> {
      let maybe_player =
        row
        |> list.map(get_player_to_player)
        |> array_to_option()

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

pub fn update_player(player: Player, db_conn: sqlight.Connection) {
  let player_id = uuid.to_string(player.id)
  let sql_result =
    sql.update_player(id: player_id, name: player.name)
    |> parrot.run_query(db_conn)

  case sql_result {
    Ok(row) -> {
      io.println(string.inspect(row))
      let maybe_player =
        row
        |> list.map(update_player_to_player)
        |> array_to_option()

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
