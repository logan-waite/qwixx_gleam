DROP TABLE IF EXISTS players;
CREATE TABLE players (
	id	TEXT PRIMARY KEY,
	name text 
);

DROP TABLE IF EXISTS games;
CREATE TABLE games (
	id	TEXT PRIMARY KEY,
	code TEXT UNIQUE NOT NULL,
	status TEXT DEFAULT 'lobby'
);

DROP TABLE IF EXISTS player_game;
CREATE TABLE player_game (
	id INTEGER PRIMARY KEY,
	player_id TEXT NOT NULL,
	game_id TEXT NOT NULL,
	joined STRING DEFAULT (datetime('subsec')),
	ready INTEGER DEFAULT FALSE,
	red INTEGER DEFAULT 0, -- Bitmask
	yellow INTEGER DEFAULT 0, -- Bitmask
	green INTEGER DEFAULT 0, -- Bitmask
	blue INTEGER DEFAULT 0, -- Bitmask
	missed INTEGER DEFAULT 0,
	FOREIGN KEY (player_id)
		REFERENCES players (id),
	FOREIGN KEY (game_id)
		REFERENCES games (id)
); 
