import gleam/dynamic/decode
import gleam/json
import youid/uuid.{type Uuid}

import shared/dice
import shared/utils

// Game
pub type GameStatus {
  Lobby
  InProgress
  Finished
}

pub type Game {
  Game(
    id: Uuid,
    code: String,
    status: GameStatus,
    // dice_state: dice.DiceState,
    // current_turn: Int,
  )
}

pub fn empty_game() {
  Game(id: uuid.nil, code: "00000", status: Lobby)
}

// Game Encoder/Decoder
fn game_status_decoder() -> decode.Decoder(GameStatus) {
  use game_status <- decode.then(decode.string)
  case game_status {
    "lobby" -> decode.success(Lobby)
    "in-progress" -> decode.success(InProgress)
    "finished" -> decode.success(Finished)
    _ -> decode.failure(Lobby, expected: "GameStatus")
  }
}

pub fn game_decoder() -> decode.Decoder(Game) {
  // use dice_state <- decode.field("dice_state", dice.dice_state_decoder())
  // use current_turn <- decode.field("current_turn", decode.int)
  use id <- decode.field("id", utils.uuid_decoder())
  use code <- decode.field("code", decode.string)
  use status <- decode.field("status", game_status_decoder())

  decode.success(Game(id:, code:, status:))
}

fn game_status_to_string(status: GameStatus) -> String {
  case status {
    Lobby -> "lobby"
    InProgress -> "in-progress"
    Finished -> "finished"
  }
}

pub fn game_status_from_string(status: String) -> GameStatus {
  case status {
    "lobby" -> Lobby
    "in-progress" -> InProgress
    "finished" -> Finished
    _ -> panic as "unhandled game status"
  }
}

pub fn game_to_json(game: Game) -> json.Json {
  let Game(id:, code:, status:) = game

  json.object([
    #("id", json.string(id |> uuid.to_string())),
    #("code", json.string(code)),
    #("status", json.string(game_status_to_string(status))),
  ])
}
