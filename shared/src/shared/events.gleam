import gleam/dynamic/decode
import gleam/json
import shared/dice.{type DiceState}

// {
//   event: String,
//   data: {
//     ... (possibly empty)
//   }
// }

pub type WsEvent {
  RollDice
  UpdatedDiceState(DiceState)
  NoOp
}

pub fn event_decoder() -> decode.Decoder(WsEvent) {
  use event <- decode.field("event", decode.string)

  case event {
    "roll-dice" -> decode.success(RollDice)
    "updated-dice-state" -> {
      use dice_state <- decode.field("data", dice.dice_state_decoder())
      decode.success(UpdatedDiceState(dice_state))
    }
    _ -> decode.success(NoOp)
  }
}

pub fn event_to_json(event: WsEvent) -> json.Json {
  case event {
    RollDice -> json.object([#("event", json.string("roll-dice"))])
    UpdatedDiceState(dice_state) ->
      json.object([
        #("event", json.string("updated-dice-state")),
        #("data", dice.dice_state_to_json(dice_state)),
      ])
    NoOp -> json.object([#("event", json.string("no-op"))])
  }
}
