import client/routes.{type Route}
import shared/player.{type Player}

pub type Context {
  Context(player: Player, current_route: Route)
}
