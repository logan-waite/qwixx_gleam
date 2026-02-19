import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_websocket as ws
import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type WsEvent}
import shared/player.{type Player, type ScoreCard, Player, ScoreCard}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", [])

  Nil
}

// Model -----------------------------------------

type Model {
  Model(
    ws: Option(ws.WebSocket),
    dice_state: DiceState,
    errors: String,
    name: String,
    score_card:ScoreCard,
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  // dice tray
  let red = Die(locked: False, value: 1)
  let yellow = Die(locked: False, value: 1)
  let blue = Die(locked: False, value: 1)
  let green = Die(locked: False, value: 1)
  let white_1 = Die(locked: False, value: 1)
  let white_2 = Die(locked: False, value: 1)
  let dice_state = DiceState(red:, yellow:, blue:, green:, white_1:, white_2:)

  // player
  let name = "Logan"
  let score_card =
    ScoreCard(red: [5], yellow: [2], green: [11], blue: [6], missed: 0)

  #(Model(ws: None, dice_state:, name:, score_card:, errors: ""), ws.init("ws", WsWrapper))
}

// Update ----------------------------------------

type Msg {
  UserRolledDice
  UserToggledScoreBox(String)
  WsWrapper(ws.WebSocketEvent)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserRolledDice -> #(model, get_new_dice_state(model.ws))
    UserToggledScoreBox(value) -> {
      // asserting here because we defined the values we're splitting
      let assert [color, num_string] = string.split(value, "-")
      let assert Ok(number) = int.parse(num_string)

      let score_card = case color {
        "red" ->
          ScoreCard(
            ..model.score_card,
            red: list.prepend(model.score_card.red, number),
          )
        "yellow" ->
          ScoreCard(
            ..model.score_card,
            yellow: list.prepend(model.score_card.yellow, number),
          )
        "green" ->
          ScoreCard(
            ..model.score_card,
            green: list.prepend(model.score_card.green, number),
          )
        "blue" ->
          ScoreCard(
            ..model.score_card,
            blue: list.prepend(model.score_card.blue, number),
          )
        _ -> {
          io.println("Error updating scorecard, received wrong color:" <> color)
          model.score_card
        }
      }
      #(Model(..model, score_card:), effect.none())
    }
    // Websocket Messages
    WsWrapper(ws.InvalidUrl) -> panic
    WsWrapper(ws.OnOpen(socket)) -> #(
      Model(..model, ws: Some(socket)),
      ws.send(socket, "client-init"),
    )
    WsWrapper(ws.OnTextMessage(msg)) -> {
      case json.parse(msg, events.event_decoder()) {
        Ok(event) -> handle_ws_event(model, event)
        Error(err) -> {
          io.println_error("error in decoding")
          #(model, effect.none())
        }
      }
    }
    WsWrapper(ws.OnBinaryMessage(msg)) -> #(model, effect.none())
    WsWrapper(ws.OnClose(reason)) -> #(model, effect.none())
  }
}

fn handle_ws_event(model: Model, event: WsEvent) -> #(Model, Effect(Msg)) {
  case event {
    events.UpdatedDiceState(dice_state) -> #(
      Model(..model, dice_state:),
      effect.none(),
    )
    // server events/empty event
    events.RollDice | events.NoOp -> #(model, effect.none())
  }
}

fn get_new_dice_state(socket: Option(ws.WebSocket)) -> Effect(Msg) {
  case socket {
    Some(s) -> ws.send(s, "roll-dice")
    None -> {
      io.println("Socket not initiated")
      effect.none()
    }
  }
}

// View ------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.button([event.on_click(UserRolledDice)], [html.text("Roll Dice")]),
    dice_tray(model.dice_state),
    score_card(model.score_card),
  ])
}

// Dice Tray
fn dice_tray(dice_state: DiceState) {
  html.div([], [
    html.ul([], [
      html.li([], [
        html.text("Red: " <> int.to_string(dice_state.red.value)),
      ]),
      html.li([], [
        html.text("Yellow: " <> int.to_string(dice_state.yellow.value)),
      ]),
      html.li([], [
        html.text("Blue: " <> int.to_string(dice_state.blue.value)),
      ]),
      html.li([], [
        html.text("Green: " <> int.to_string(dice_state.green.value)),
      ]),
      html.li([], [
        html.text("White 1: " <> int.to_string(dice_state.white_1.value)),
      ]),
      html.li([], [
        html.text("White 2: " <> int.to_string(dice_state.white_2.value)),
      ]),
    ]),
  ])
}

// Score Card
fn score_box(id, content, is_selected) {
  html.label([attr.for(id)], [
    html.input([
      attr.type_("checkbox"),
      attr.id(id),
      attr.value(id),
      attr.checked(is_selected),
      event.on_change(UserToggledScoreBox),
    ]),
    html.text(content),
  ])
}

fn score_row(color, selected_nums) {
  let boxes =
    int.range(from: 2, to: 14, with: [], run: fn(acc, i: Int) {
      let num = int.to_string(i)
      let is_selected = list.contains(selected_nums, i)

      { color <> "-" <> num }
      |> score_box(num, is_selected)
      |> list.prepend(acc, _)
    })
    |> list.reverse()

  html.div([], [html.text(color), ..boxes])
}

fn score_card(card: ScoreCard) {
  html.div([], [
    score_row("red", card.red),
    score_row("yellow", card.yellow),
    score_row("green", card.green),
    score_row("blue", card.blue),
  ])
}
