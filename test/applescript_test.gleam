import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import things_mcp/applescript
import things_mcp/tools/todo_ops
import things_mcp/types
import things_mcp/write_checks

@external(erlang, "applescript_test_ffi", "timeout_stops_direct_process")
fn timeout_stops_direct_process() -> Result(Nil, String)

pub fn timeout_terminates_direct_process_test() {
  timeout_stops_direct_process() |> should.equal(Ok(Nil))
}

pub fn escaped_text_round_trips_without_things_test() {
  list.each(
    [
      "backslash \\\" quoted",
      "first\nsecond\rthird\tcolumn\n",
      "æøå 🦦 é",
      "\\n literal",
    ],
    fn(value) {
      applescript.execute("return " <> applescript.quote_string(value))
      |> should.equal(Ok(value <> "\n"))
    },
  )
}

pub fn calendar_date_fields_are_locale_independent_test() {
  list.each(["2028-02-29", "2000-02-29", "2029-01-31", "2026-04-30"], fn(value) {
    let assert Ok(script) = applescript.calendar_date_script(value)
    applescript.execute(
      script
      <> "return ((year of requestedDate) as string) & \"-\" & ((month of requestedDate as integer) as string) & \"-\" & ((day of requestedDate) as string) & \"/\" & (time of requestedDate as string)",
    )
    |> should.equal(
      Ok(case value {
        "2028-02-29" -> "2028-2-29/0\n"
        "2000-02-29" -> "2000-2-29/0\n"
        "2029-01-31" -> "2029-1-31/0\n"
        _ -> "2026-4-30/0\n"
      }),
    )
  })
}

pub fn invalid_dates_fail_before_any_things_write_test() {
  todo_ops.handle_create_todo(types.CreateTodoArgs(
    "not created",
    None,
    Some("2026-02-29"),
    None,
    None,
  ))
  |> should.be_error
  todo_ops.handle_update_todo(types.UpdateTodoArgs(
    "not accessed",
    None,
    None,
    Some("2026-04-31"),
    None,
  ))
  |> should.be_error
}

pub fn execution_errors_retain_codes_without_echoing_secrets_test() {
  let assert Error(error) =
    applescript.execute_write(
      "error \"synthetic-secret https://example.test/?token=secret\" number -1700",
    )
  string.contains(error, "AppleScript code -1700") |> should.be_true
  string.contains(error, "required property type") |> should.be_true
  string.contains(error, "synthetic-secret") |> should.be_false
  string.contains(error, "token=") |> should.be_false
  string.contains(error, "timed out") |> should.be_false
  string.contains(error, "do not retry automatically") |> should.be_true
}

pub fn start_failures_are_distinct_test() {
  let assert Error(error) =
    applescript.run("/no/such/things-mcp-executable", [], 100)
  string.contains(error, "could not start; no command dispatched")
  |> should.be_true
}

pub fn process_and_apple_event_timeouts_are_distinct_test() {
  let assert Error(error) =
    applescript.run("/usr/bin/osascript", ["-e", "delay 2"], 100)
  string.contains(error, "process timed out and was stopped") |> should.be_true
  let assert Error(event_error) =
    applescript.execute_write("error \"private\" number -1712")
  string.contains(event_error, "AppleScript code -1712") |> should.be_true
  string.contains(event_error, "Things may still finish") |> should.be_true
}

pub fn verification_failure_retains_created_id_test() {
  write_checks.created("known-id", Error("read failed"))
  |> should.equal(Error("read failed\nCreated ID: known-id"))
}
