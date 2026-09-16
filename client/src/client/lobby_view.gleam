import gleam/io
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp

import client/context.{type Context, Context}
import shared/player.{type Player, Player} as app_player

// -----------------------------------------------
// Model -----------------------------------------
// -----------------------------------------------
pub type Model {
  Model(temp_name: String)
}

pub fn new_model() {
  Model(temp_name: "")
}

// -----------------------------------------------
// Update ----------------------------------------
// -----------------------------------------------
pub type Msg {
  UserSavedName
  UserUpdatedName(String)
  ServerReturnedPlayer(Result(Player, rsvp.Error(String)))
}

pub fn update(
  context: Context,
  model: Model,
  msg: Msg,
) -> #(Context, Model, Effect(Msg)) {
  case msg {
    UserSavedName -> update_player_name(context, model)
    UserUpdatedName(name) -> #(
      context,
      Model(..model, temp_name: name),
      effect.none(),
    )
    ServerReturnedPlayer(req_result) -> {
      case req_result {
        Ok(player) -> #(Context(..context, player:), model, effect.none())
        Error(error) -> {
          io.println(
            "error from ServerReturnedPlayer: " <> string.inspect(error),
          )
          #(context, model, effect.none())
        }
      }
    }
  }
}

fn update_player_name(
  context: Context,
  model: Model,
) -> #(Context, Model, Effect(Msg)) {
  let player = Player(..context.player, name: Some(model.temp_name))
  let new_model = Model(..model, temp_name: "")

  let url = "/api/player"
  let body = app_player.player_to_json(player)

  let effect =
    rsvp.put(
      url,
      body,
      rsvp.expect_json(app_player.player_decoder(), ServerReturnedPlayer),
    )

  // Send updated name to server
  #(Context(..context, player: player), new_model, effect)
}

// -----------------------------------------------
// View ------------------------------------------
// -----------------------------------------------
pub fn view(context: Context, model: Model) -> Element(Msg) {
  let player = context.player
  let name = case player.name {
    Some(name) -> name
    None -> "Guest"
  }
  html.div([], [
    html.text("Lobby for game " <> context.game.code <> "!"),
    html.div([], [
      html.div([], [
        html.text("player name: " <> name),
      ]),
      html.div([], [
        html.text("change name: "),
        html.input([
          attr.type_("text"),
          event.on_input(UserUpdatedName),
          attr.value(model.temp_name),
        ]),
        html.button(
          [
            event.on_click(UserSavedName),
          ],
          [html.text("Save")],
        ),
      ]),
    ]),
  ])
}
