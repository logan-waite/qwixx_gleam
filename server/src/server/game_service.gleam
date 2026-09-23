import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import sqlight
import wisp
import youid/uuid

import server/parrot
import server/sql
import shared/game.{type Game, Game} as app_game
import shared/utils

pub fn create_game(db_conn: sqlight.Connection) -> Game {
  let code = get_game_code(db_conn)
  let id = uuid.v4() |> uuid.to_string()
  let sql = sql.add_game(id: id, code: code, status: "lobby")
  case parrot.run_query(sql, db_conn) {
    Ok(row) -> {
      let maybe_game =
        row
        |> list.map(add_game_to_game)
        |> utils.unwrap_list()
      case maybe_game {
        Some(game) -> game
        None -> {
          io.println("game not returned?")
          app_game.empty_game()
        }
      }
    }
    Error(err) -> {
      todo
    }
  }
}

pub fn get_game_by_code(code: String, db_conn: sqlight.Connection) {
  let sql = sql.get_game_with_code(code)
  case parrot.run_query(sql, db_conn) {
    Ok(row) -> {
      let maybe_game =
        row
        |> list.map(get_game_by_code_to_game)
        |> utils.unwrap_list()
      case maybe_game {
        Some(game) -> {
          let return_body = app_game.game_to_json(game) |> json.to_string()
          wisp.ok()
          |> wisp.json_body(return_body)
        }
        None -> wisp.not_found()
      }
    }
    Error(err) -> {
      todo
    }
  }
}

fn add_game_to_game(add_game: sql.AddGame) -> Game {
  let sql.AddGame(id:, code:, status:) = add_game
  let assert Ok(game_id) = uuid.from_string(id)
  let status = status |> app_game.game_status_from_string()
  Game(id: game_id, code:, status:)
}

fn get_game_by_code_to_game(get_game: sql.GetGameWithCode) -> Game {
  let sql.GetGameWithCode(id:, code:, status:) = get_game
  let assert Ok(game_id) = uuid.from_string(id)
  let status = status |> app_game.game_status_from_string()
  Game(id: game_id, code:, status:)
}

fn generate_game_code() -> String {
  // five random letters (all caps)
  // leads to ≈12m combos
  "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
  |> string.split("")
  |> list.sample(5)
  |> list.shuffle()
  |> string.join("")
}

fn get_game_code(db_conn: sqlight.Connection) {
  get_game_code_recursive([], db_conn)
}

fn get_game_code_recursive(
  codes_checked: List(String),
  db_conn: sqlight.Connection,
) -> String {
  let new_code = generate_game_code()
  case list.contains(codes_checked, new_code) {
    True -> get_game_code_recursive(codes_checked, db_conn)
    False -> {
      let sql = sql.get_game_with_code(new_code)
      case parrot.run_query(sql, db_conn) {
        Ok(row) -> {
          case utils.unwrap_list(row) {
            Some(_) -> {
              let codes = list.prepend(codes_checked, new_code)
              get_game_code_recursive(codes, db_conn)
            }
            None -> {
              new_code
            }
          }
        }
        Error(err) -> {
          io.println(string.inspect(err))
          ""
        }
      }
    }
  }
}
