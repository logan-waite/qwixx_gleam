import gleam/io
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/time/timestamp
import sqlight
import youid/uuid

import server/database/parrot
import server/database/sql
import shared/game.{type Game, type GameCode, Game} as app_game
import shared/player.{type Player, type PlayerGame, Player, PlayerGame}
import shared/utils

// --------------------
// Player DB Operations
// --------------------
pub fn add_player(player player: Player, db_conn db_conn: sqlight.Connection) {
  let player_id =
    player.id
    |> uuid.to_string

  let sql_result = sql.add_player(player_id, player.name)

  case parrot.run_query(sql_result, db_conn) {
    Ok(row) -> row |> list.map(add_player__player) |> utils.unwrap_list
    Error(err) -> {
      let error = "db error in db.add_player: " <> string.inspect(err)
      Error(error)
    }
  }
}

pub fn get_player(id id: String, db_conn db_conn: sqlight.Connection) {
  let sql_result = sql.get_player(id)

  case parrot.run_query(sql_result, db_conn) {
    Ok(row) -> {
      row |> list.map(get_player__player) |> utils.unwrap_list()
    }
    Error(err) -> {
      let error = "db error in db.get_player: " <> string.inspect(err)
      Error(error)
    }
  }
}

pub fn update_player(
  player player: Player,
  db_conn db_conn: sqlight.Connection,
) {
  let player_id = uuid.to_string(player.id)
  let sql_result = sql.update_player(id: player_id, name: player.name)

  case parrot.run_query(sql_result, db_conn) {
    Ok(row) -> {
      row
      |> list.map(update_player__player)
      |> utils.unwrap_list()
    }
    Error(err) -> {
      let error = "db error in db.update_player: " <> string.inspect(err)
      Error(error)
    }
  }
}

// --------------------
// PlayerGame DB Operations
// --------------------
pub fn add_player_game(
  player player: Player,
  game game: Game,
  db_conn db_conn: sqlight.Connection,
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
      player_id: player.id |> uuid.to_string(),
      game_id: game.id |> uuid.to_string,
      joined: joined,
      ready: False,
      red: 0,
      yellow: 0,
      green: 0,
      blue: 0,
      missed: 0,
    )
  case parrot.run_query(sql_result, db_conn) {
    Ok(row) -> {
      row
      |> list.map(add_player_game__player_game(_, player.name, game.code))
      |> utils.unwrap_list()
    }
    Error(err) -> {
      let error = "db error in db.add_player_game: " <> string.inspect(err)
      Error(error)
    }
  }
}

pub fn get_player_game(
  player_id player_id: String,
  game_code game_code: GameCode,
  db_conn db_conn: sqlight.Connection,
) {
  let sql_params = sql.get_player_game(player_id, game_code)
  case parrot.run_query(sql_params, db_conn) {
    Ok(row) -> {
      row |> list.map(get_player_game__player_game) |> utils.unwrap_list()
    }
    Error(err) -> {
      let error = "db error in db.add_player_game: " <> string.inspect(err)
      Error(error)
    }
  }
}

pub fn update_player_game(
  player_game: PlayerGame,
  db_conn: sqlight.Connection,
) {
  let PlayerGame(
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
    id:,
    game_code:,
    name:,
    player_id: _,
    joined: _,
  ) = player_game

  let sql_params =
    sql.update_player_game(
      ready:,
      red:,
      yellow:,
      green:,
      blue:,
      missed:,
      id: id |> uuid.to_string(),
    )
  case parrot.run_query(sql_params, db_conn) {
    Ok(row) -> {
      row
      |> list.map(update_player_game__player_game(_, name, game_code))
      |> utils.unwrap_list()
    }
    Error(err) -> {
      let error = "db error in db.add_player_game: " <> string.inspect(err)
      Error(error)
    }
  }
}

pub fn get_game_players(
  game_code game_code: GameCode,
  db_conn db_conn: sqlight.Connection,
) {
  let sql_result = sql.get_player_games_with_game_code(game_code)
  case parrot.run_query(sql_result, db_conn) {
    Ok(rows) -> {
      rows |> list.map(get_player_game_with_game_code__player_game) |> Ok
    }
    Error(err) -> {
      let error = "db error in db.get_game_players: " <> string.inspect(err)
      Error(error)
    }
  }
}

// --------------------
// Game DB Operations
// --------------------
pub fn add_game(db_conn db_conn: sqlight.Connection) {
  let code = create_game_code(db_conn)
  let id = uuid.v4() |> uuid.to_string()
  let sql = sql.add_game(id: id, code: code, status: "lobby")
  case parrot.run_query(sql, db_conn) {
    Ok(row) -> {
      row
      |> list.map(add_game__game)
      |> utils.unwrap_list()
    }
    Error(err) -> {
      let error = "db error in db.add_game: " <> string.inspect(err)
      Error(error)
    }
  }
}

fn create_game_code(db_conn: sqlight.Connection) {
  let codes = case sql.get_all_game_codes() |> parrot.run_query(db_conn) {
    Ok(rows) -> {
      rows |> list.map(get_all_game_codes__game_code)
    }
    Error(err) -> {
      io.println("error getting game codes: " <> string.inspect(err))
      []
    }
  }

  generate_unique_game_code(codes)
  // get_game_code_recursive([], db_conn)
}

fn generate_unique_game_code(existing_codes: List(String)) {
  // five random letters (all caps)
  // leads to ≈12m combos
  let code =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    |> string.split("")
    |> list.sample(5)
    |> list.shuffle()
    |> string.join("")

  case list.contains(existing_codes, code) {
    True -> generate_unique_game_code(existing_codes)
    False -> code
  }
}

pub fn get_game_by_code(
  code code: GameCode,
  db_conn db_conn: sqlight.Connection,
) {
  let sql = sql.get_game_with_code(code)
  case parrot.run_query(sql, db_conn) {
    Ok(rows) -> {
      rows |> list.map(get_game_with_code__game) |> utils.unwrap_list()
    }
    Error(err) -> {
      let error = "db error in db.get_game_with_code: " <> string.inspect(err)
      Error(error)
    }
  }
}

// --------------------
// Mapping Functions
// --------------------
fn add_player__player(add_player: sql.AddPlayer) -> Player {
  let sql.AddPlayer(id:, name:) = add_player
  let assert Ok(player_id) = uuid.from_string(id)
  Player(id: player_id, name:)
}

fn get_player__player(get_player: sql.GetPlayer) -> Player {
  let sql.GetPlayer(id:, name:) = get_player
  let assert Ok(player_id) = uuid.from_string(id)
  Player(id: player_id, name:)
}

fn update_player__player(update_player: sql.UpdatePlayer) -> Player {
  let sql.UpdatePlayer(id:, name:) = update_player
  let assert Ok(player_id) = uuid.from_string(id)
  Player(id: player_id, name:)
}

fn add_player_game__player_game(
  add_player_game: sql.AddPlayerGame,
  name: Option(String),
  game_code: app_game.GameCode,
) {
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
  let joined =
    timestamp.from_unix_seconds_and_nanoseconds(
      joined / 1_000_000_000,
      joined % 1_000_000_000,
    )

  PlayerGame(
    id:,
    player_id:,
    game_code:,
    name:,
    joined:,
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
  )
}

fn get_player_game__player_game(
  get_player_game: sql.GetPlayerGame,
) -> PlayerGame {
  let sql.GetPlayerGame(
    id:,
    player_id:,
    name:,
    game_id:,
    game_code:,
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
  let joined =
    timestamp.from_unix_seconds_and_nanoseconds(
      joined / 1_000_000_000,
      joined % 1_000_000_000,
    )

  PlayerGame(
    id:,
    player_id:,
    name:,
    game_code:,
    joined:,
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
  )
}

fn update_player_game__player_game(
  add_player_game: sql.UpdatePlayerGame,
  name: Option(String),
  game_code: app_game.GameCode,
) {
  let sql.UpdatePlayerGame(
    id:,
    player_id:,
    game_id: _,
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
  let joined =
    timestamp.from_unix_seconds_and_nanoseconds(
      joined / 1_000_000_000,
      joined % 1_000_000_000,
    )

  PlayerGame(
    id:,
    player_id:,
    game_code:,
    name:,
    joined:,
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
  )
}

fn get_player_game_with_game_code__player_game(
  get_player_game: sql.GetPlayerGamesWithGameCode,
) {
  let sql.GetPlayerGamesWithGameCode(
    id:,
    player_id:,
    name:,
    game_id:,
    game_code:,
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
  let joined =
    timestamp.from_unix_seconds_and_nanoseconds(
      joined / 1_000_000_000,
      joined % 1_000_000_000,
    )

  PlayerGame(
    id:,
    player_id:,
    game_code:,
    joined:,
    ready:,
    red:,
    yellow:,
    green:,
    blue:,
    missed:,
    name:,
  )
}

fn add_game__game(add_game: sql.AddGame) -> Game {
  let sql.AddGame(id:, code:, status:) = add_game
  let assert Ok(game_id) = uuid.from_string(id)
  let status = status |> app_game.game_status_from_string()
  Game(id: game_id, code:, status:)
}

fn get_all_game_codes__game_code(
  get_all_game_codes: sql.GetAllGameCodes,
) -> GameCode {
  let sql.GetAllGameCodes(code:) = get_all_game_codes
  code
}

fn get_game_with_code__game(get_game: sql.GetGameWithCode) -> Game {
  let sql.GetGameWithCode(id:, code:, status:) = get_game
  let assert Ok(game_id) = uuid.from_string(id)
  let status = status |> app_game.game_status_from_string()
  Game(id: game_id, code:, status:)
}
