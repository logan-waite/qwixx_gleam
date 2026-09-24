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
import shared/player.{type Player, type PlayerGame, Player, PlayerGame} as app_player

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
  ServerCheckedPlayerInGame(Result(PlayerGame, rsvp.Error(String)))
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
          case game.status {
            app_game.Lobby -> {
              // if the game is in lobby, join the game.
              let new_context = Context(..context, game:)
              #(
                new_context,
                model,
                modem.push("lobby/" <> game.code, None, None),
              )
            }
            _ -> {
              let new_context = Context(..context, game:)
              let url =
                "/api/game/"
                <> game.code
                <> "/player/"
                <> context.player.id |> uuid.to_string()
              let effect =
                rsvp.get(
                  url,
                  rsvp.expect_json(
                    app_player.player_game_decoder(),
                    ServerCheckedPlayerInGame,
                  ),
                )
              #(new_context, model, effect)
            }
          }
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
    ServerCheckedPlayerInGame(req_result) -> {
      io.println(
        "ServerCheckedPLayerInGame game status: "
        <> context.game |> string.inspect(),
      )
      case req_result {
        Ok(_) -> {
          // If player is in the game and it's active, just go straight there.
          case context.game.status {
            app_game.InProgress -> #(
              context,
              model,
              modem.push("game/" <> context.game.code, None, None),
            )

            app_game.Finished -> #(
              context,
              model,
              modem.push("finish/" <> context.game.code, None, None),
            )

            _ -> {
              // Lobby games should be handle by previous check
              io.println(
                "trying to join lobby game after having checked game wasn't in lobby",
              )
              #(context, model, effect.none())
            }
          }
        }
        Error(err) -> {
          // If player isn't a part of the game, error out.
          case err {
            rsvp.HttpError(response) -> {
              let response.Response(status:, body:, headers:) = response
              let error = case status {
                404 ->
                  "Cannot join game "
                  <> model.code
                  <> ". Please try another game"
                _ -> "An unknown error occurred while trying to join game"
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
