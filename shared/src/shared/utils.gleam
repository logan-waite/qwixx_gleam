import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/time/timestamp.{type Timestamp}
import youid/uuid.{type Uuid}

pub fn uuid_decoder() -> decode.Decoder(Uuid) {
  decode.string
  |> decode.then(fn(str) {
    case uuid.from_string(str) {
      Ok(id) -> decode.success(id)
      Error(_) if str == "" -> decode.success(uuid.nil)
      Error(_) -> decode.failure(uuid.nil, "Uuid")
    }
  })
}

pub fn timestamp_to_json(ts: Timestamp) -> json.Json {
  let time = timestamp.to_unix_seconds_and_nanoseconds(ts)
  json.array(
    [
      time.0,
      time.1,
    ],
    of: json.int,
  )
}

pub fn timestamp_decoder() -> decode.Decoder(Timestamp) {
  decode.list(decode.int)
  |> decode.then(fn(time) {
    case time {
      [s, ns] ->
        decode.success(timestamp.from_unix_seconds_and_nanoseconds(s, ns))
      _ -> decode.success(timestamp.system_time())
    }
  })
}
