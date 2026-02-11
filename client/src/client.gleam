import gleam/int
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import lustre
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import lustre_websocket as ws
import rsvp
import shared/dice.{type DiceState, DiceState, Die}
import shared/events.{type WsEvent}

pub fn main() -> Nil {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", [])

  Nil
}

// Model -----------------------------------------

type Model {
  Model(ws: Option(ws.WebSocket), dice_state: DiceState, errors: String)
}

fn init(_) -> #(Model, Effect(Msg)) {
  let red = Die(locked: False, value: 1)
  let yellow = Die(locked: False, value: 1)
  let blue = Die(locked: False, value: 1)
  let green = Die(locked: False, value: 1)
  let white_1 = Die(locked: False, value: 1)
  let white_2 = Die(locked: False, value: 1)
  let dice_state = DiceState(red:, yellow:, blue:, green:, white_1:, white_2:)

  #(Model(ws: None, dice_state:, errors: ""), ws.init("ws", WsWrapper))
}

// Update ----------------------------------------

type Msg {
  UserRolledDice
  ApiUpdatedDiceState(Result(DiceState, rsvp.Error))
  WsWrapper(ws.WebSocketEvent)
}

fn update(model: Model, msg: Msg) -> #(Model, Effect(Msg)) {
  case msg {
    UserRolledDice -> #(model, get_new_dice_state(model.ws))
    ApiUpdatedDiceState(result) ->
      case result {
        Ok(dice_state) -> #(Model(..model, dice_state:), effect.none())
        Error(_) -> #(Model(..model, errors: "An error occured"), effect.none())
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
  // let url = "/api/roll-dice"
  // let handler = rsvp.expect_json(dice.dice_state_decoder(), ApiUpdatedDiceState)
  //
  // rsvp.get(url, handler)
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
