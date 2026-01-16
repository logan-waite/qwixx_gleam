import gleam/dynamic/decode
import gleam/json
import shared/dice

// Game
pub type GameStatus {
  Lobby
  InProgress
  Finished
}

pub type Game {
  Game(
    dice_state: dice.DiceState,
    current_turn: Int,
    game_code: String,
    game_status: GameStatus,
  )
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
  use dice_state <- decode.field("dice_state", dice.dice_state_decoder())
  use current_turn <- decode.field("current_turn", decode.int)
  use game_code <- decode.field("game_code", decode.string)
  use game_status <- decode.field("game_status", game_status_decoder())

  decode.success(Game(dice_state:, current_turn:, game_code:, game_status:))
}

fn game_status_to_string(status: GameStatus) -> String {
  case status {
    Lobby -> "lobby"
    InProgress -> "in-progress"
    Finished -> "finished"
  }
}

pub fn game_to_json(game: Game) -> json.Json {
  let Game(dice_state:, current_turn:, game_code:, game_status:) = game

  json.object([
    #("dice_state", dice.dice_state_to_json(dice_state)),
    #("current_turn", json.int(current_turn)),
    #("game_code", json.string(game_code)),
    #("game_status", json.string(game_status_to_string(game_status))),
  ])
}
