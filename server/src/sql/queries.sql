-----------
-- PLAYERS
-----------

-- name: AddPlayer :one
INSERT INTO players (
	id, name 
) VALUES (
	?, ?
)
RETURNING *;

-- name: GetPlayer :one
SELECT * FROM players
WHERE id = ?;

-- name: UpdatePlayer :one
UPDATE players
SET name = ?
WHERE id = ?
RETURNING *;

-----------
-- GAMES
-----------

-- name: AddGame :one
INSERT INTO games (
	id, code, status 
) VALUES (
	?, ?, ?
)
RETURNING *;

-- name: GetGames :many
SELECT * FROM games;

-- name: GetGameWithCode :one
SELECT * FROM games
WHERE code = ?;

-- name: GetAllGameCodes :many
SELECT code from games;

-- name: UpdateGame :one
UPDATE games
SET status = ?
WHERE code = ?
RETURNING *;

-----------
-- PLAYER GAMES
-----------

-- name: AddPlayerGame :one
INSERT INTO player_games (
	id, player_id, game_id, joined, ready, red, yellow, green, blue, missed
) VALUES (
	?, ?, ?, ?, ?, ?, ?, ?, ?, ?
)
RETURNING *;

-- name: GetPlayerGame :one
SELECT players.name, games.code game_code, player_games.* FROM player_games
JOIN games ON games.id = player_games.game_id
JOIN players on players.id = player_games.player_id
WHERE player_games.player_id = ? AND games.code = ?;

-- name: UpdatePlayerGame :one
UPDATE player_games
SET ready = ?,
red = ?,
yellow = ?,
green = ?,
blue = ?,
missed = ?
WHERE id = ?
RETURNING *;

-- name: GetPlayerGamesWithGameCode :many
SELECT player_games.*, players.name, games.code game_code FROM player_games
JOIN games on player_games.game_id = games.id
JOIN players on players.id = player_games.player_id
WHERE code = ?;

-- name: SetAllPlayerReadyStatus :exec
UPDATE player_games
SET ready = ?
WHERE game_id = (
	SELECT id
	FROM games
	WHERE code = ?
);

