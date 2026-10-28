import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/time/timestamp.{type Timestamp}
import youid/uuid.{type Uuid}

import shared/game
import shared/utils

pub type Player {
  Player(id: Uuid, name: Option(String))
}

pub type PlayerGame {
  PlayerGame(
    id: Uuid,
    player_id: Uuid,
    name: Option(String),
    game_code: game.GameCode,
    joined: Timestamp,
    ready: Bool,
    // red bitmask
    red: Int,
    // yellow bitmask
    yellow: Int,
    // green bitmask
    green: Int,
    // blue bitmask
    blue: Int,
    missed: Int,
  )
}

pub fn new_player() -> Player {
  Player(id: uuid.nil, name: None)
}

pub fn new_player_game(player: Player, game_code: game.GameCode) -> PlayerGame {
  PlayerGame(
    id: uuid.nil,
    player_id: player.id,
    name: player.name,
    game_code:,
    joined: timestamp.system_time(),
    ready: False,
    red: 0,
    yellow: 0,
    green: 0,
    blue: 0,
    missed: 0,
  )
}

pub fn player_decoder() -> decode.Decoder(Player) {
  use name <- decode.field("name", decode.optional(decode.string))
  use id_string <- decode.field("id", decode.string)

  case uuid.from_string(id_string) {
    Ok(id) -> decode.success(Player(id:, name:))
    Error(_) -> decode.failure(Player(id: uuid.nil, name:), "Player")
  }
}

pub fn player_to_json(player: Player) -> json.Json {
  let Player(id:, name:) = player

  json.object([
    #("id", json.string(uuid.to_string(id))),
    #("name", json.nullable(name, json.string)),
  ])
}

pub fn player_game_decoder() -> decode.Decoder(PlayerGame) {
  use id <- decode.field("id", utils.uuid_decoder())
  use player_id <- decode.field("player_id", utils.uuid_decoder())
  use name <- decode.field("name", decode.optional(decode.string))
  use game_code <- decode.field("game_code", decode.string)
  use joined <- decode.field("joined", utils.timestamp_decoder())
  use ready <- decode.field("ready", decode.bool)
  use red <- decode.field("red", decode.int)
  use yellow <- decode.field("yellow", decode.int)
  use green <- decode.field("green", decode.int)
  use blue <- decode.field("blue", decode.int)
  use missed <- decode.field("missed", decode.int)

  decode.success(PlayerGame(
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
  ))
}

pub fn player_game_to_json(player_game: PlayerGame) -> json.Json {
  let PlayerGame(
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
  ) = player_game

  json.object([
    #("id", json.string(uuid.to_string(player_id))),
    #("player_id", json.string(uuid.to_string(player_id))),
    #("name", json.nullable(name, json.string)),
    #("game_code", json.string(game_code)),
    #("joined", utils.timestamp_to_json(joined)),
    #("ready", json.bool(ready)),
    #("red", json.int(red)),
    #("yellow", json.int(yellow)),
    #("green", json.int(green)),
    #("blue", json.int(blue)),
    #("missed", json.int(missed)),
  ])
}
