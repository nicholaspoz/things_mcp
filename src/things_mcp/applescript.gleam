import gleam/list
import gleam/result
import gleam/string
import things_mcp/validation

/// Execute an AppleScript command and return the result or error
pub fn execute(script: String) -> Result(String, String) {
  run("/usr/bin/osascript", ["-e", script], 10_000)
}

/// Wrap a command in a "tell application Things3" block
pub fn tell_things(command: String) -> String {
  "tell application \"Things3\"\n" <> command <> "\nend tell"
}

/// Build a property map string for AppleScript from a list of key-value pairs
/// Example: [#("name", "\"Test\""), #("notes", "\"Some notes\"")]
/// becomes: {name:"Test", notes:"Some notes"}
pub fn build_properties(props: List(#(String, String))) -> String {
  case props {
    [] -> "{}"
    _ -> {
      props
      |> list.map(fn(prop) {
        let #(key, value) = prop
        key <> ":" <> value
      })
      |> string.join(", ")
      |> fn(s) { "{" <> s <> "}" }
    }
  }
}

/// Build a Things object reference by stable Things ID.
pub fn todo_by_id(id: String) -> String {
  "to do id " <> quote_string(id)
}

pub fn project_by_id(id: String) -> String {
  "project id " <> quote_string(id)
}

pub fn area_by_id(id: String) -> String {
  "area id " <> quote_string(id)
}

/// Quote a string for use in AppleScript
pub fn quote_string(s: String) -> String {
  "\"" <> escape_quotes(s) <> "\""
}

/// Escape quotes in a string for AppleScript
fn escape_quotes(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
  |> string.replace("\n", "\\n")
  |> string.replace("\r", "\\r")
}

pub fn execute_write(script: String) -> Result(String, String) {
  run("/usr/bin/osascript", ["-e", script], 10_000)
  |> result.map_error(fn(error) {
    error
    <> "; earlier changes may have applied; inspect the item before retrying; do not retry automatically"
  })
}

// AppleScript's date-string parser depends on locale and can reinterpret ISO
// input. Construct the local calendar date explicitly, with a safe day first.
pub fn calendar_date_script(value: String) -> Result(String, String) {
  use _ <- result.try(validation.validate_date(value))
  let assert [year, month, day] = string.split(value, "-")
  Ok(
    "set requestedDate to current date\n"
    <> "set day of requestedDate to 1\n"
    <> "set year of requestedDate to "
    <> year
    <> "\n"
    <> "set month of requestedDate to "
    <> month
    <> "\n"
    <> "set day of requestedDate to "
    <> day
    <> "\n"
    <> "set time of requestedDate to 0\n",
  )
}

/// Bounded direct subprocess used for AppleScript and isolated runner tests.
@external(erlang, "things_applescript_ffi", "run")
pub fn run(
  command: String,
  args: List(String),
  timeout: Int,
) -> Result(String, String)

@external(erlang, "things_applescript_ffi", "sleep")
pub fn sleep(milliseconds: Int) -> Nil
