import gleam/dynamic/decode
import gleam/http/response
import gleam/int
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
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
  Model(code: String, error: Option(String))
}

pub fn new_model() {
  Model(code: "", error: None)
}

// -----------------------------------------------
// Update ----------------------------------------
// -----------------------------------------------

pub type Msg {
  UserCreateGame
  UserUpdatedGameCode(String)
  UserAttemptedJoinGame
  ServerCreatedGame(Result(Game, rsvp.Error(String)))
  ServerFoundGame(Result(Game, rsvp.Error(String)))
}

pub fn update(
  context: Context,
  model: Model,
  msg: Msg,
) -> #(Context, Model, Effect(Msg)) {
  case msg {
    // User Actions
    UserCreateGame -> create_game(context, model)
    UserUpdatedGameCode(code) -> #(
      context,
      Model(..model, code:),
      effect.none(),
    )
    UserAttemptedJoinGame -> attempt_join_game(context, model)
    // Server Responses
    ServerCreatedGame(req_result) -> {
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
    ServerFoundGame(req_result) -> {
      case req_result {
        Ok(game) -> {
          let new_context = Context(..context, game:)
          #(new_context, model, modem.push("lobby/" <> game.code, None, None))
        }
        Error(err) -> {
          case err {
            rsvp.HttpError(response) -> {
              let response.Response(status:, body:, headers:) = response
              let error = case status {
                404 ->
                  "Game " <> model.code <> " not found. Please try another game"
                _ -> "An unknown error occurred while looking for the game"
              }
              #(context, Model(..model, error: Some(error)), effect.none())
            }
            _ -> {
              io.println("rsvp gave back a weird error:" <> string.inspect(err))
              #(context, model, effect.none())
            }
          }
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
      rsvp.expect_json(app_game.game_decoder(), ServerCreatedGame),
    )

  #(context, model, effect)
}

fn attempt_join_game(
  context: Context,
  model: Model,
) -> #(Context, Model, Effect(Msg)) {
  // check for game
  // if found, and in lobby, go to game
  // if found, and not in lobby, error
  // if not found, error
  let url = "/api/game/" <> model.code

  let effect =
    rsvp.get(url, rsvp.expect_json(app_game.game_decoder(), ServerFoundGame))

  #(context, model, effect)
}

// -----------------------------------------------
// View ------------------------------------------
// -----------------------------------------------

pub fn view(context: Context, model: Model) -> Element(Msg) {
  let error_box = case model.error {
    Some(error) -> {
      html.div([attr.styles([#("background-color", "lightcoral")])], [
        html.text(error),
      ])
    }
    None -> html.div([], [])
  }
  html.div([], [
    error_box,
    html.div([], [
      html.text("Join an existing game:"),
      html.input([
        attr.type_("text"),
        event.on_input(UserUpdatedGameCode),
        attr.value(model.code),
      ]),
      html.button([event.on_click(UserAttemptedJoinGame)], [
        html.text("Join Game"),
      ]),
    ]),
    html.div([], [
      html.text("Or start a new one:"),
      html.button([event.on_click(UserCreateGame)], [html.text("New Game")]),
    ]),
  ])
}
