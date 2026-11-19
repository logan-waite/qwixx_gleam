import gleam/float
import gleam/int
import gleam/list
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event

import client/shared.{type Context, Context}
import shared/dice
import shared/events as app_events
import shared/player.{type PlayerGame, PlayerGame} as app_player

// -----------------------------------------------
// Model -----------------------------------------
// -----------------------------------------------

pub type Model {
  Model
}

pub fn new_model() {
  Model
}

// -----------------------------------------------
// Update ----------------------------------------
// -----------------------------------------------

pub type Msg {
  UserRolledDice
  UserToggledScoreBox(String)
}

pub fn update(
  context: Context,
  model: Model,
  msg: Msg,
) -> #(Context, Model, Effect(Msg)) {
  case msg {
    UserRolledDice -> #(
      context,
      model,
      shared.send_event(context.ws, app_events.RollDice),
    )
    UserToggledScoreBox(value) -> {
      let player_game = update_player_game(context.player_game, value)
      #(Context(..context, player_game:), model, effect.none())
    }
  }
}

fn update_player_game(player_game: PlayerGame, value: String) {
  // asserting here because we defined the values we're splitting
  let assert [color_string, num_string] = string.split(value, "-")
  let assert Ok(number) = int.parse(num_string)
  let assert Ok(color) = app_player.parse_player_game_color(color_string)
  // get the bitmask value
  let assert Ok(bit_float) = int.power(2, int.to_float(number - 1))
  let bit_value = float.round(bit_float)

  let player_game = case color {
    app_player.Red ->
      PlayerGame(..player_game, red: player_game.red + bit_value)
    app_player.Yellow ->
      PlayerGame(..player_game, yellow: player_game.yellow + bit_value)
    app_player.Green ->
      PlayerGame(..player_game, green: player_game.green + bit_value)
    app_player.Blue ->
      PlayerGame(..player_game, blue: player_game.blue + bit_value)
  }
  player_game
}

// -----------------------------------------------
// View ------------------------------------------
// -----------------------------------------------

pub fn view(context: Context, model: Model) -> Element(Msg) {
  html.div([], [
    html.button([event.on_click(UserRolledDice)], [html.text("Roll Dice")]),
    dice_tray(context.game.dice_state),
    score_card(context.player_game),
  ])
}

fn dice_tray(dice_state: dice.DiceState) {
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

fn score_row(color, bitmask) {
  let boxes =
    int.range(from: 13, to: 1, with: [], run: fn(acc, i: Int) {
      let assert Ok(exp) = int.power(2, int.to_float(i - 1))
      let value = float.round(exp) |> int.bitwise_and(bitmask)
      let is_selected = value > 0

      let num = int.to_string(i)
      { color <> "-" <> num }
      |> score_box(num, is_selected)
      |> list.prepend(acc, _)
    })

  html.div([], [html.text(color), ..boxes])
}

fn score_card(game: app_player.PlayerGame) {
  html.div([], [
    score_row("red", game.red),
    score_row("yellow", game.yellow),
    score_row("green", game.green),
    score_row("blue", game.blue),
  ])
}
