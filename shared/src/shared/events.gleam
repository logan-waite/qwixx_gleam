import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import shared/dice.{type DiceState}
import shared/player.{type Player}

// {
//   event: String,
//   data: {
//     ... (possibly empty)
//   }
// }

pub type AppEvent {
  RollDice
  UpdatedDiceState(DiceState)
  PlayerUpdatedScoreCard(Player)
  // App Status
  SocketConnected(Player)
  NoOp
}

pub fn event_decoder() -> decode.Decoder(AppEvent) {
  use event <- decode.field("event", decode.string)

  case event {
    "roll-dice" -> decode.success(RollDice)
    "updated-dice-state" -> {
      use dice_state <- decode.field("data", dice.dice_state_decoder())
      decode.success(UpdatedDiceState(dice_state))
    }
    "player-updated-score-card" -> {
      use player <- decode.field("data", player.player_decoder())
      decode.success(PlayerUpdatedScoreCard(player))
    }
    "socket-connected" -> {
      use player <- decode.field("data", player.player_decoder())
      decode.success(SocketConnected(player))
    }
    _ -> decode.success(NoOp)
  }
}

pub fn parse_event(msg: String) -> AppEvent {
  case json.parse(msg, event_decoder()) {
    Ok(event) -> event
    Error(err) -> {
      case err {
        json.UnexpectedEndOfInput -> io.println("unexpected end of input")
        json.UnexpectedByte(str) -> io.println("unexpected byte: " <> str)
        json.UnexpectedSequence(str) ->
          io.println("unexpected sequence: " <> str)
        json.UnableToDecode(decode_errors) -> {
          io.println("errors when decodeing:")
          list.map(decode_errors, fn(error) {
            let decode.DecodeError(expected:, found:, path:) = error
            io.println("expected: " <> expected)
            io.println("found: " <> found)
            io.println("path: " <> string.join(path, "."))
          })
          Nil
        }
      }
      NoOp
    }
  }
}

fn to_event(name: String, json_data: Option(json.Json)) -> json.Json {
  case json_data {
    Some(data) -> json.object([#("event", json.string(name)), #("data", data)])
    None -> json.object([#("event", json.string(name))])
  }
}

pub fn event_to_json(event: AppEvent) -> json.Json {
  case event {
    RollDice -> to_event("roll-dice", None)
    UpdatedDiceState(dice_state) ->
      to_event("updated-dice-state", Some(dice.dice_state_to_json(dice_state)))
    PlayerUpdatedScoreCard(player) ->
      to_event("player-updated-score-card", Some(player.player_to_json(player)))
    SocketConnected(player) ->
      to_event("socket-connected", Some(player.player_to_json(player)))
    NoOp -> to_event("no-op", None)
  }
}

pub fn event_to_text(event: AppEvent) -> String {
  event_to_json(event) |> json.to_string
}
