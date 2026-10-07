import client/routes.{type Route}
import shared/game.{type Game}
import shared/player.{type Player, type PlayerGame}

pub type Context {
  Context(
    player: Player,
    current_route: Route,
    game: Game,
    player_game: PlayerGame,
  )
}
