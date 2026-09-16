import gleam/dynamic/decode
import gleam/http/response
import gleam/io
import gleam/json
import gleam/option.{None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import modem
import rsvp
import youid/uuid.{type Uuid}

import client/context.{type Context, Context}
import client/local_data.{LocalData}
import client/routes.{type Route}
import shared/game.{type Game} as app_game
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
  UserCreateGame
  ServerReturnedGame(Result(Game, rsvp.Error(String)))
}

pub fn update(
  context: Context,
  model: Model,
  msg: Msg,
) -> #(Context, Model, Effect(Msg)) {
  case msg {
    // User Actions
    UserCreateGame -> create_game(context, model)
    // Server Responses
    ServerReturnedGame(req_result) -> {
      case req_result {
        Ok(game) -> {
          let new_context = Context(..context, game:)
          #(new_context, model, modem.push("lobby/" <> game.code, None, None))
        }
        Error(err) -> {
          io.println(string.inspect(err))
          #(context, model, effect.none())
        }
      }
    }
  }
}

fn create_game(
  context: Context,
  model: Model,
) -> #(Context, Model, Effect(Msg)) {
  let url = "/api/game"
  let body = app_player.player_to_json(context.player)

  let effect =
    rsvp.post(
      url,
      body,
      rsvp.expect_json(app_game.game_decoder(), ServerReturnedGame),
    )

  #(context, model, effect)
}

// -----------------------------------------------
// View ------------------------------------------
// -----------------------------------------------

pub fn view(context: Context, model: Model) -> Element(Msg) {
  html.div([], [
    html.div([], [
      html.text("Join an existing game:"),
      html.input([attr.type_("text")]),
      html.button([], [html.text("Join Game")]),
    ]),
    html.div([], [
      html.text("Or start a new one:"),
      html.button([event.on_click(UserCreateGame)], [html.text("New Game")]),
    ]),
  ])
}
