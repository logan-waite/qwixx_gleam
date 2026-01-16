import rsvp
import gleam/int
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import shared/dice.{type DiceState, DiceState, Die}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", [])

  Nil
}

// Model -----------------------------------------

type Model {
  Model(dice_state: DiceState, errors: String)
}

fn init(_) -> #(Model, Effect(Msg)) {
  let red = Die(locked: False, value: 1)
  let yellow = Die(locked: False, value: 1)
  let blue = Die(locked: False, value: 1)
  let green = Die(locked: False, value: 1)
  let white_1 = Die(locked: False, value: 1)
  let white_2 = Die(locked: False, value: 1)
  let dice_state = DiceState(red:, yellow:, blue:, green:, white_1:, white_2:)

  #(Model(dice_state:, errors: ""), effect.none())
}

// Update ----------------------------------------

type Msg {
  UserRolledDice
ApiUpdatedDiceState(Result(DiceState, rsvp.Error))
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserRolledDice -> #(model, get_new_dice_state())
    ApiUpdatedDiceState(result) -> case result {
      Ok(dice_state) -> #(Model(..model, dice_state:), effect.none())
      Error(_) -> #(Model(..model, errors: "An error occured"), effect.none())
    }
  }
}

fn get_new_dice_state() -> Effect(Msg) {
  let url = "/api/roll-dice"
  let handler = rsvp.expect_json(dice.dice_state_decoder(), ApiUpdatedDiceState)

  rsvp.get(url, handler)
}

// View ------------------------------------------

fn view(model: Model) -> Element(Msg) {
  html.div([], [
    html.button([event.on_click(UserRolledDice)], [html.text("Roll Dice")]),
    html.div([], [
      html.ul([], [
        html.li([], [
          html.text("Red: " <> int.to_string(model.dice_state.red.value)),
        ]),
        html.li([], [
          html.text("Yellow: " <> int.to_string(model.dice_state.yellow.value)),
        ]),
        html.li([], [
          html.text("Blue: " <> int.to_string(model.dice_state.blue.value)),
        ]),
        html.li([], [
          html.text("Green: " <> int.to_string(model.dice_state.green.value)),
        ]),
        html.li([], [
          html.text(
            "White 1: " <> int.to_string(model.dice_state.white_1.value),
          ),
        ]),
        html.li([], [
          html.text(
            "White 2: " <> int.to_string(model.dice_state.white_2.value),
          ),
        ]),
      ]),
    ]),
  ])
}
