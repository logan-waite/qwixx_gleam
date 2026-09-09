import server/sql
import shared/player.{type Player, Player}
import youid/uuid

pub type SqlPlayer {
  Add(sql.AddPlayer)
  Get(sql.GetPlayer)
}

pub fn sql_player_to_player(sql_player: SqlPlayer) -> Player {
  case sql_player {
    Add(player) -> {
      let sql.AddPlayer(id:, name:) = player
      let assert Ok(player_id) = uuid.from_string(id)
      Player(id: player_id, name:)
    }
    Get(player) -> {
      let sql.GetPlayer(id:, name:) = player
      let assert Ok(player_id) = uuid.from_string(id)
      Player(id: player_id, name:)
    }
  }
}
