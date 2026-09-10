import gleam/dynamic/decode
import gleam/io
import gleam/json
import gleam/result
import youid/uuid

pub type LocalDataError {
  RetrievalError
  DecoderError(json.DecodeError)
}

@external(javascript, "../client.ffi.mjs", "get_localstorage")
fn get_localstorage(_key: String) -> Result(String, LocalDataError) {
  Error(RetrievalError)
}

@external(javascript, "../client.ffi.mjs", "set_localstorage")
fn set_localstorage(_key: String, _value: String) -> Nil {
  Nil
}

pub type LocalData {
  LocalData(player_id: uuid.Uuid)
}

fn local_data_decoder() -> decode.Decoder(LocalData) {
  use player_id <- decode.field("player_id", decode.string)
  let assert Ok(uuid) = uuid.from_string(player_id)
  io.println("saved id: " <> uuid.to_string(uuid))
  decode.success(LocalData(player_id: uuid))
}

fn local_data_to_json(data: LocalData) -> json.Json {
  let LocalData(player_id:) = data

  json.object([#("player_id", json.string(uuid.to_string(player_id)))])
}

pub fn get() -> Result(LocalData, LocalDataError) {
  get_localstorage("qwixx")
  |> result.try(fn(string) {
    json.parse(string, local_data_decoder())
    |> result.map_error(DecoderError)
  })
}

pub fn save(data: LocalData) -> Nil {
  let local_data_string = local_data_to_json(data) |> json.to_string()

  set_localstorage("qwixx", local_data_string)
}
