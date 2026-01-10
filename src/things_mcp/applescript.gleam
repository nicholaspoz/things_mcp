import gleam/int
import gleam/list
import gleam/result
import gleam/string
import shellout

/// Execute an AppleScript command and return the result or error
pub fn execute(script: String) -> Result(String, String) {
  shellout.command(run: "osascript", with: ["-e", script], in: ".", opt: [])
  |> result.map_error(fn(err) {
    let #(code, message) = err
    "AppleScript error (code " <> int.to_string(code) <> "): " <> message
  })
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

/// Quote a string for use in AppleScript
pub fn quote_string(s: String) -> String {
  "\"" <> escape_quotes(s) <> "\""
}

/// Escape quotes in a string for AppleScript
fn escape_quotes(s: String) -> String {
  string.replace(s, "\"", "\\\"")
}
