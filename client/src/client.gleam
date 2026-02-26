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
import youid/uuid

import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type AppEvent}
import shared/player.{type Player, type ScoreCard, Player, ScoreCard}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", [])

  Nil
}

// -----------------------------------------------
// Model -----------------------------------------
// -----------------------------------------------

type Model {
  Model(
    ws: Option(ws.WebSocket),
    dice_state: DiceState,
    errors: String,
    player: Player,
  )
}

fn init(_) -> #(Model, Effect(Msg)) {
  let dice_state = dice.new_dice_state()
  let player = player.new_player()
  #(Model(ws: None, dice_state:, player:, errors: ""), ws.init("ws", WsWrapper))
}

// -----------------------------------------------
// Update ----------------------------------------
// -----------------------------------------------

type Msg {
  UserRolledDice
  UserToggledScoreBox(String)
  WsWrapper(ws.WebSocketEvent)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserRolledDice -> #(model, send_event(model.ws, events.RollDice))
    UserToggledScoreBox(value) -> update_score_card(model, value)
    // Websocket Messages
    WsWrapper(event) -> handle_ws_event(model, event)
  }
}

fn handle_ws_event(model: Model, ws_event: ws.WebSocketEvent) {
  case ws_event {
    ws.InvalidUrl -> panic
    ws.OnOpen(socket) -> #(
      Model(..model, ws: Some(socket)),
      send_event(Some(socket), events.NoOp),
    )
    ws.OnTextMessage(msg) -> {
      events.parse_event(msg)
      |> handle_app_event(model)
    }
    ws.OnBinaryMessage(_msg) -> #(model, effect.none())
    ws.OnClose(_reason) -> #(model, effect.none())
  }
}

fn handle_app_event(event: AppEvent, model: Model) -> #(Model, Effect(Msg)) {
  case event {
    events.UpdatedDiceState(dice_state) -> #(
      Model(..model, dice_state:),
      effect.none(),
    )
    events.SocketConnected(player) -> {
      #(Model(..model, player: player), effect.none())
    }
    _ -> #(model, effect.none())
  }
}

fn send_event(socket, event) {
  case socket {
    Some(s) -> ws.send(s, events.event_to_text(event))
    None -> {
      io.println("Socket not initiated")
      effect.none()
    }
  }
}

// Dice

// Score Card
fn update_score_card(model: Model, value: String) {
  // asserting here because we defined the values we're splitting
  let assert [color, num_string] = string.split(value, "-")
  let assert Ok(number) = int.parse(num_string)

  let score_card = case color {
    "red" ->
      ScoreCard(
        ..model.player.score_card,
        red: list.prepend(model.player.score_card.red, number),
      )
    "yellow" ->
      ScoreCard(
        ..model.player.score_card,
        yellow: list.prepend(model.player.score_card.yellow, number),
      )
    "green" ->
      ScoreCard(
        ..model.player.score_card,
        green: list.prepend(model.player.score_card.green, number),
      )
    "blue" ->
      ScoreCard(
        ..model.player.score_card,
        blue: list.prepend(model.player.score_card.blue, number),
      )
    _ -> {
      io.println("Error updating scorecard, received wrong color:" <> color)
      model.player.score_card
    }
  }
  io.println(
    "updated score_card: "
    <> player.score_card_to_json(score_card) |> json.to_string(),
  )
  let player = Player(..model.player, score_card:)
  #(
    Model(..model, player:),
    send_event(model.ws, events.PlayerUpdatedScoreCard(player)),
  )
}

// -----------------------------------------------
// View ------------------------------------------
// -----------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.button([event.on_click(UserRolledDice)], [html.text("Roll Dice")]),
    dice_tray(model.dice_state),
    score_card(model.player.score_card),
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
