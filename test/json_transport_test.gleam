import gleam/dict
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleam/uri
import gleeunit/should
import things_mcp/json_transport as transport

@external(erlang, "transport_test_ffi", "invalid_token_is_sanitized")
fn invalid_token_is_sanitized() -> Result(Nil, String)

@external(erlang, "transport_test_ffi", "timeout_stops_direct_process")
fn timeout_stops_direct_process() -> Result(Nil, String)

fn callback(status: String, ids: String) -> String {
  json.object([
    #("status", json.string(status)),
    #("parameters", json.object([#("x-things-ids", json.string(ids))])),
  ])
  |> json.to_string
}

pub fn url_encoding_preserves_data_and_callback_routes_test() {
  let payload = "[{\"notes\":\"æøå 🦦 \\n &?=#%+\"}]"
  let token = "synthetic-token+&=#%"
  let nonce = "0123456789abcdef0123456789abcdef"
  let assert Ok(parsed) =
    transport.build_url(payload, Some(token), nonce) |> uri.parse
  parsed.scheme |> should.equal(Some("things"))
  parsed.path |> should.equal("/json")
  let assert Some(query) = parsed.query
  let assert Ok(pairs) = uri.parse_query(query)
  let parameters = dict.from_list(pairs)
  dict.size(parameters) |> should.equal(6)
  dict.get(parameters, "data") |> should.equal(Ok(payload))
  dict.get(parameters, "auth-token") |> should.equal(Ok(token))
  dict.get(parameters, "reveal") |> should.equal(Ok("false"))
  list.each(["success", "error", "cancel"], fn(status) {
    dict.get(parameters, "x-" <> status)
    |> should.equal(Ok("things-mcp-callback://" <> nonce <> "/" <> status))
  })
}

pub fn creation_url_omits_authorization_test() {
  let url = transport.build_url("[]", None, "nonce")
  string.contains(url, "auth-token") |> should.be_false
}

pub fn create_callback_requires_exactly_one_nonempty_id_test() {
  transport.decode_callback(callback("success", "[\"stable-id\"]"), False)
  |> should.equal(Ok(Some("stable-id")))
  list.each(
    ["[]", "[\"one\",\"two\"]", "[\"\"]", "[null]", "[1]", "id", "{}"],
    fn(ids) {
      transport.decode_callback(callback("success", ids), False)
      |> should.be_error
    },
  )
  transport.decode_callback("{\"status\":\"success\",\"parameters\":{}}", False)
  |> should.be_error
}

pub fn update_success_does_not_require_created_ids_test() {
  transport.decode_callback("{\"status\":\"success\",\"parameters\":{}}", True)
  |> should.equal(Ok(None))
  transport.decode_callback(callback("success", "[]"), True)
  |> should.equal(Ok(None))
}

pub fn failed_and_malformed_callbacks_never_report_success_or_echo_input_test() {
  list.each(
    [
      callback("error", "synthetic-secret"),
      callback("cancel", "synthetic-secret"),
      callback("unknown", "synthetic-secret"),
      "synthetic-secret",
      "{}",
      "{\"status\":\"success\"}",
      "{\"status\":1,\"parameters\":{}}",
      "{\"status\":\"success\",\"parameters\":{\"x-things-ids\":1}}",
    ],
    fn(encoded) {
      list.each([True, False], fn(updating) {
        let assert Error(message) = transport.decode_callback(encoded, updating)
        string.contains(message, "synthetic-secret") |> should.be_false
      })
    },
  )
}

pub fn subprocess_arguments_preserve_unicode_without_shell_expansion_test() {
  let text = "æøå 🦦 'quoted' \"double\" $HOME `literal` ; &\nnext"
  transport.run("/usr/bin/printf", ["%s", text], 2000)
  |> should.equal(Ok(text))
}

pub fn subprocess_failure_does_not_expose_output_or_arguments_test() {
  let assert Error(message) =
    transport.run(
      "/bin/sh",
      ["-c", "printf synthetic-secret >&2; exit 1"],
      2000,
    )
  string.contains(message, "synthetic-secret") |> should.be_false
  transport.run("/nonexistent/synthetic-secret", [], 2000)
  |> should.equal(Error("Could not start local command"))
}

pub fn malformed_token_file_returns_sanitized_error_test() {
  invalid_token_is_sanitized() |> should.equal(Ok(Nil))
}

pub fn timeout_terminates_the_direct_executable_test() {
  timeout_stops_direct_process() |> should.equal(Ok(Nil))
}
