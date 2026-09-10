import gleam/dynamic/decode
import gleam/io
import gleam/list
import gleam/string
import parrot/dev
import sqlight

fn parrot_to_sqlight(param: dev.Param) -> sqlight.Value {
  case param {
    dev.ParamFloat(x) -> sqlight.float(x)
    dev.ParamInt(x) -> sqlight.int(x)
    dev.ParamString(x) -> sqlight.text(x)
    dev.ParamBitArray(x) -> sqlight.blob(x)
    dev.ParamNullable(x) -> sqlight.nullable(fn(a) { parrot_to_sqlight(a) }, x)
    dev.ParamList(_) -> panic as "sqlite does not implement lists"
    dev.ParamBool(_) -> panic as "sqlite does not support booleans"
    dev.ParamDate(_) -> panic as "sqlite does not support dates"
    dev.ParamTimestamp(_) -> panic as "sqlite does not support timestamps"
    dev.ParamDynamic(_) -> todo
  }
}

pub fn run_query(
  query_info: #(String, List(dev.Param), decode.Decoder(d)),
  conn: sqlight.Connection,
) -> Result(List(d), sqlight.Error) {
  let #(sql, params, expecting) = query_info
  let with = list.map(params, parrot_to_sqlight)
  sqlight.query(sql, conn, with, expecting)
}
