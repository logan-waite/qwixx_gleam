import gleam/dynamic/decode
import gleam/json

pub type Player {
  Player(name: String, score_card: ScoreCard)
}

pub type ScoreRow =
  List(Int)

pub type ScoreCard {
  ScoreCard(
    red: ScoreRow,
    yellow: ScoreRow,
    green: ScoreRow,
    blue: ScoreRow,
    missed: Int,
  )
}

//{
//  name: String
//  score_card: {
//    red: [],
//    yellow: [],
//    green: [],
//    blue: []
//    missed: 0
//  }
//}
fn score_card_decoder() -> decode.Decoder(ScoreCard) {
  use red <- decode.field("red", decode.list(decode.int))
  use yellow <- decode.field("yellow", decode.list(decode.int))
  use green <- decode.field("green", decode.list(decode.int))
  use blue <- decode.field("blue", decode.list(decode.int))
  use missed <- decode.field("missed", decode.int)

  decode.success(ScoreCard(red:, yellow:, green:, blue:, missed:))
}

pub fn player_decoder() -> decode.Decoder(Player) {
  use name <- decode.field("name", decode.string)
  use score_card <- decode.field("score_card", score_card_decoder())

  decode.success(Player(name:, score_card:))
}

fn score_card_to_json(score_card: ScoreCard) -> json.Json {
  let ScoreCard(red:, yellow:, green:, blue:, missed:) = score_card

  json.object([
    #("red", json.array(red, json.int)),
    #("yellow", json.array(yellow, json.int)),
    #("green", json.array(green, json.int)),
    #("blue", json.array(blue, json.int)),
    #("missed", json.int(missed)),
  ])
}

pub fn player_to_json(player: Player) -> json.Json {
  let Player(name:, score_card:) = player

  json.object([
    #("name", json.string(name)),
    #("score_card", score_card_to_json(score_card)),
  ])
}
