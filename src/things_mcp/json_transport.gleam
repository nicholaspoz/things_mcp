import gleam/dynamic/decode
import gleam/json
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import gleam/uri

@external(erlang, "things_json_ffi", "prepare")
fn prepare() -> Result(#(String, String), String)

@external(erlang, "things_json_ffi", "dispatch")
fn dispatch(directory: String, url: String) -> Result(Nil, String)

@external(erlang, "things_json_ffi", "await_callback")
fn await_callback(directory: String, timeout: Int) -> Result(String, String)

@external(erlang, "things_json_ffi", "cleanup")
fn cleanup(directory: String) -> Nil

@external(erlang, "things_json_ffi", "auth_token")
fn auth_token() -> Result(String, String)

@external(erlang, "things_json_ffi", "run")
pub fn run(
  command: String,
  arguments: List(String),
  timeout: Int,
) -> Result(String, String)

@external(erlang, "things_json_ffi", "sleep")
pub fn sleep(milliseconds: Int) -> Nil

pub fn execute(
  payload: String,
  updating: Bool,
) -> Result(Option(String), String) {
  use token <- result.try(case updating {
    True -> result.map(auth_token(), Some)
    False -> Ok(None)
  })
  use request <- result.try(prepare())
  let #(nonce, directory) = request
  let outcome = execute_request(payload, updating, token, nonce, directory)
  cleanup(directory)
  outcome
}

fn execute_request(
  payload: String,
  updating: Bool,
  token: Option(String),
  nonce: String,
  directory: String,
) -> Result(Option(String), String) {
  let url = build_url(payload, token, nonce)
  use _ <- result.try(dispatch(directory, url))
  use callback <- result.try(await_callback(directory, 15_000))
  decode_callback(callback, updating)
}

// Pure to make encoding and callback contracts testable without opening Things.
pub fn build_url(
  payload: String,
  token: Option(String),
  nonce: String,
) -> String {
  let callback = "things-mcp-callback://" <> nonce <> "/"
  "things:///json?reveal=false&data="
  <> encode_query(payload)
  <> case token {
    Some(value) -> "&auth-token=" <> encode_query(value)
    None -> ""
  }
  <> "&x-success="
  <> encode_query(callback <> "success")
  <> "&x-error="
  <> encode_query(callback <> "error")
  <> "&x-cancel="
  <> encode_query(callback <> "cancel")
}

pub fn decode_callback(
  callback: String,
  updating: Bool,
) -> Result(Option(String), String) {
  let decoder = {
    use status <- decode.field("status", decode.string)
    use ids <- decode.field("parameters", {
      use ids <- decode.optional_field(
        "x-things-ids",
        None,
        decode.optional(decode.string),
      )
      decode.success(ids)
    })
    decode.success(#(status, ids))
  }
  use response <- result.try(
    json.parse(callback, decoder)
    |> result.map_error(fn(_) {
      "Malformed Things callback; completion is uncertain"
    }),
  )
  case response {
    #("success", _) if updating -> Ok(None)
    #("success", Some(ids)) -> {
      case json.parse(ids, decode.list(decode.string)) {
        Ok([id]) if id != "" -> Ok(Some(id))
        _ ->
          Error(
            "Things create callback did not return exactly one ID; completion is uncertain",
          )
      }
    }
    #("success", None) ->
      Error("Things create callback omitted its ID; completion is uncertain")
    #("error", _) ->
      Error(
        "Things rejected the JSON request; changes may be partial; do not retry automatically",
      )
    #("cancel", _) ->
      Error("Things JSON request was canceled; completion is uncertain")
    _ -> Error("Unknown Things callback status; completion is uncertain")
  }
}

fn encode_query(value: String) -> String {
  uri.percent_encode(value) |> string.replace("+", "%2B")
}
