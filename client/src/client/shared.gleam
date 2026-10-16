import gleam/io
import gleam/option.{type Option, None, Some}
import lustre/effect
import lustre_websocket as ws

import shared/events
import shared/game.{type Game}
import shared/player.{type Player, type PlayerGame}

pub type Route {
  Start
  Lobby(String)
  Game(String)
  Finish(String)
}

pub type Context {
  Context(
    ws: Option(ws.WebSocket),
    player: Player,
    current_route: Route,
    game: Game,
    player_game: PlayerGame,
  )
}

pub fn send_event(socket, event) {
  case socket {
    Some(s) -> ws.send(s, events.event_to_text(event))
    None -> {
      io.println("Socket not initiated")
      effect.none()
    }
  }
}
