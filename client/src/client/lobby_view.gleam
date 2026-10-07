import gleam/http/response
import gleam/io
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/string
import lustre/attribute as attr
import lustre/effect.{type Effect}
import lustre/element.{type Element}
import lustre/element/html
import lustre/event
import rsvp
import youid/uuid.{type Uuid}

import client/context.{type Context, Context}
import client/routes.{Lobby}
import shared/game.{type Game} as app_game
import shared/player.{type Player, type PlayerGame, Player} as app_player

// -----------------------------------------------
// Model -----------------------------------------
// -----------------------------------------------
pub type Model {
  Model(temp_name: String)
}

pub fn new_model() {
  Model(temp_name: "")
}

pub fn init(context: Context, model: Model) -> #(Context, Model, Effect(Msg)) {
  // need to load game, in case we don't have it already.
  // also need to get the player game if available, else create one.
  // chain will be load game -> get player game -> (?) create player game

  let game_code = case context.current_route {
    Lobby(code) -> code
    _ -> panic as "on lobby page without being on lobby route"
  }
  let effect =
    rsvp.get(
      "/api/game/" <> game_code,
      rsvp.expect_json(app_game.game_decoder(), ServerReturnedGame),
    )
  #(context, model, effect)
}

// -----------------------------------------------
// Update ----------------------------------------
// -----------------------------------------------
pub type Msg {
  UserSavedName
  UserUpdatedName(String)
  ServerReturnedPlayer(Result(Player, rsvp.Error(String)))
  ServerReturnedGame(Result(Game, rsvp.Error(String)))
  ServerReturnedPlayerGame(Result(PlayerGame, rsvp.Error(String)))
  ServerCreatedPlayerGame(Result(PlayerGame, rsvp.Error(String)))
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
    ServerReturnedGame(req_result) -> {
      // now get the player game with the new game id
      case req_result {
        Ok(game) -> {
          let new_context = Context(..context, game:)
          let effect = get_player_game(context.player.id, game.code)
          #(new_context, model, effect)
        }
        Error(err) -> {
          io.println("no player_game: " <> string.inspect(err))
          #(context, model, effect.none())
        }
      }
    }
    ServerReturnedPlayerGame(req_result) -> {
      case req_result {
        Ok(player_game) -> {
          let new_context = Context(..context, player_game:)
          #(new_context, model, effect.none())
        }
        Error(err) -> {
          io.println("need to create a player game")
          case err {
            rsvp.HttpError(response) -> {
              let response.Response(status, _body, _headers) = response
              let err = case status {
                404 -> {
                  let effect =
                    create_player_game(context.player.id, context.game.code)
                  #(context, model, effect)
                }
                _ -> {
                  io.println(
                    "An unknown error occurred while trying to create a game",
                  )
                  todo
                }
              }
            }
            _ -> {
              io.println(
                "rsvp gave back a weird error: " <> string.inspect(err),
              )
              #(context, model, effect.none())
            }
          }
        }
      }
    }
    ServerCreatedPlayerGame(req_result) -> {
      case req_result {
        Ok(player_game) -> {
          let new_context = Context(..context, player_game:)
          #(new_context, model, effect.none())
        }
        Error(_err) -> {
          io.println("error creating game")
          #(context, model, effect.none())
        }
      }
    }
  }
}

fn get_player_game(player_id: Uuid, game_code: String) {
  let url =
    "/api/game/" <> game_code <> "/player/" <> player_id |> uuid.to_string()
  rsvp.get(
    url,
    rsvp.expect_json(app_player.player_game_decoder(), ServerReturnedPlayerGame),
  )
}

fn create_player_game(player_id: Uuid, game_code: String) {
  let url = "/api/game/" <> game_code <> "/player/"
  let body =
    json.object([#("player_id", json.string(player_id |> uuid.to_string()))])
  rsvp.post(
    url,
    body,
    rsvp.expect_json(app_player.player_game_decoder(), ServerCreatedPlayerGame),
  )
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
    html.div([], [
      html.span([attr.style("font-weight", "bold")], [html.text("Players")]),
    ]),
  ])
}
