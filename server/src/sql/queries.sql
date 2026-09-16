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

-- name: UpdateGame :one
UPDATE games
SET status = ?
WHERE id = ?
RETURNING *;

-- name: AddPlayerGame :one
INSERT INTO player_games (
	id, player_id, game_id, joined, ready, red, yellow, green, blue, missed
) VALUES (
	?, ?, ?, ?, ?, ?, ?, ?, ?, ?
)
RETURNING *;

-- name: GetPlayerGame :one
SELECT * FROM player_games
WHERE player_id = ? AND game_id = ?;

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

-- name: GetPlayerGamesWithGameId :many
SELECT * FROM player_games
WHERE game_id = ?;
