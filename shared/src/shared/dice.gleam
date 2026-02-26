import gleam/dynamic/decode
import gleam/json

// Dice types
pub type DieColor {
  Red
  Yellow
  Green
  Blue
  White
}

pub type Die {
  Die(locked: Bool, value: Int)
}

pub type DiceState {
  DiceState(
    red: Die,
    yellow: Die,
    green: Die,
    blue: Die,
    white_1: Die,
    white_2: Die,
  )
}

pub fn new_dice_state() -> DiceState {
  let red = Die(locked: False, value: 1)
  let yellow = Die(locked: False, value: 1)
  let blue = Die(locked: False, value: 1)
  let green = Die(locked: False, value: 1)
  let white_1 = Die(locked: False, value: 1)
  let white_2 = Die(locked: False, value: 1)
  DiceState(red:, yellow:, blue:, green:, white_1:, white_2:)
}

// Dice Encoder/Decoders
pub fn die_decoder() -> decode.Decoder(Die) {
  use locked <- decode.field("locked", decode.bool)
  use value <- decode.field("value", decode.int)

  decode.success(Die(locked:, value:))
}

pub fn dice_state_decoder() -> decode.Decoder(DiceState) {
  use red <- decode.field("red", die_decoder())
  use yellow <- decode.field("yellow", die_decoder())
  use green <- decode.field("green", die_decoder())
  use blue <- decode.field("blue", die_decoder())
  use white_1 <- decode.field("white_1", die_decoder())
  use white_2 <- decode.field("white_2", die_decoder())

  decode.success(DiceState(red:, yellow:, green:, blue:, white_1:, white_2:))
}

pub fn die_to_json(die: Die) -> json.Json {
  let Die(locked:, value:) = die
  json.object([
    #("locked", json.bool(locked)),
    #("value", json.int(value)),
  ])
}

pub fn dice_state_to_json(dice_state: DiceState) -> json.Json {
  let DiceState(red:, yellow:, green:, blue:, white_1:, white_2:) = dice_state
  json.object([
    #("red", die_to_json(red)),
    #("yellow", die_to_json(yellow)),
    #("green", die_to_json(green)),
    #("blue", die_to_json(blue)),
    #("white_1", die_to_json(white_1)),
    #("white_2", die_to_json(white_2)),
  ])
}
