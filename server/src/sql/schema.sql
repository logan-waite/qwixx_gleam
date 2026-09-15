DROP TABLE IF EXISTS players;
CREATE TABLE players (
	id	TEXT PRIMARY KEY,
	name text 
);

DROP TABLE IF EXISTS games;
CREATE TABLE games (
	id	TEXT PRIMARY KEY,
	code TEXT UNIQUE NOT NULL,
	status TEXT NOT NULL DEFAULT 'lobby'
);

DROP TABLE IF EXISTS player_games;
CREATE TABLE player_games (
	id TEXT PRIMARY KEY,
	player_id TEXT NOT NULL,
	game_id TEXT NOT NULL,
	joined INTEGER NOT NULL, -- Unix Timestamp (Nanosecond Precision)
	ready INTEGER NOT NULL DEFAULT FALSE,
	red INTEGER NOT NULL DEFAULT 0, -- Bitmask
	yellow INTEGER NOT NULL DEFAULT 0, -- Bitmask
	green INTEGER NOT NULL DEFAULT 0, -- Bitmask
	blue INTEGER NOT NULL DEFAULT 0, -- Bitmask
	missed INTEGER NOT NULL DEFAULT 0,
	FOREIGN KEY (player_id)
		REFERENCES players (id),
	FOREIGN KEY (game_id)
		REFERENCES games (id)
); 
