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

-- name: UpdatePlayer :exec
UPDATE players
SET name = ?
WHERE id = ?;

-- name: AddGame :one
INSERT INTO games (
	id, code 
) VALUES (
	?, ?
)
RETURNING *;

-- name: GetGames :many
SELECT * FROM games;

-- name: GetGameWithCode :one
SELECT * FROM games
WHERE code = ?;

-- name: UpdateGame :exec
UPDATE games
SET status = ?
WHERE id = ?;

-- name: AddPlayerGame :one
INSERT INTO player_game (
	player_id, game_id
) VALUES (
	?, ?
)
RETURNING *;

-- name: GetPlayerGame :one
SELECT * FROM player_game
WHERE player_id = ? AND game_id = ?;

-- name: UpdatePlayerGame :exec
UPDATE player_game
SET ready = ?,
red = ?,
yellow = ?,
green = ?,
blue = ?,
missed = ?
WHERE id = ?;
