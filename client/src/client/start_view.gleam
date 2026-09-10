import gleam/io
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import youid/uuid.{type Uuid}

import client/local_data.{LocalData}
import shared/player.{type Player, Player} as app_player

// Model
pub type Model {
  Model(temp_name: String)
}

pub fn new_model() {
  Model(temp_name: "")
}

// Update
pub type Msg {
  UserUpdatedName(String)
  UserSavedName
  ServerReturnedPlayer(Result(Player, rsvp.Error(String)))
}

pub fn update(
  player: Player,
  model: Model,
  msg: Msg,
) -> #(Player, Model, Effect(Msg)) {
  case msg {
    UserUpdatedName(name) -> #(
      player,
      Model(..model, temp_name: name),
      effect.none(),
    )
    UserSavedName -> update_player_name(player, model)
    ServerReturnedPlayer(request_result) -> {
      case request_result {
        Ok(player) -> #(
          player,
          Model(..model),
          save_player_id_locally(player.id),
        )
        Error(error) -> {
          io.println(
            "error from ServerReturnedPlayer: " <> string.inspect(error),
          )
          #(player, model, effect.none())
        }
      }
    }
  }
}

fn save_player_id_locally(player_id: Uuid) {
  use _ <- effect.from

  local_data.save(LocalData(player_id:))
}

fn update_player_name(
  player: Player,
  model: Model,
) -> #(Player, Model, Effect(Msg)) {
  let updated_player = Player(..player, name: Some(model.temp_name))
  let new_model = Model(..model, temp_name: "")

  let url = "/api/player"
  let body = app_player.player_to_json(updated_player)

  let effect =
    rsvp.put(
      url,
      body,
      rsvp.expect_json(app_player.player_decoder(), ServerReturnedPlayer),
    )

  // Send updated name to server
  #(updated_player, new_model, effect)
}

// View
pub fn view(player: Player, model: Model) -> Element(Msg) {
  let name = case player.name {
    Some(name) -> name
    None -> "Guest"
  }
  html.div([], [
    html.div([], [
      html.text("player name: " <> name),
    ]),
    html.div([], [
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
    html.div([], [
      html.text("player id:"),
      html.text(uuid.to_string(player.id)),
    ]),
    html.div([], [
      html.text("Join an existing game:"),
      html.input([attr.type_("text")]),
    ]),
    html.div([], [
      html.text("Or start a new one:"),
      html.button([], [html.text("New Game")]),
    ]),
  ])
}
