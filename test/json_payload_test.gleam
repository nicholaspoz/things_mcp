import gleam/dynamic/decode
import gleam/json
import gleam/list
import gleam/option.{None, Some}
import gleam/string
import gleeunit/should
import things_mcp/json_payload as payload
import things_mcp/types

pub fn inbox_creation_omits_schedule_and_optional_fields_test() {
  payload.create_todo(types.CreateTodoArgs("Task", None, None, None, None))
  |> should.equal(Ok(
    "[{\"type\":\"to-do\",\"operation\":\"create\",\"attributes\":{\"title\":\"Task\"}}]",
  ))
}

pub fn creation_maps_deadline_separately_from_schedule_test() {
  let assert Ok(encoded) =
    payload.create_todo(types.CreateTodoArgs(
      "Task",
      Some("Notes"),
      Some("2028-02-29"),
      Some(["Work", "Errands"]),
      Some("Today"),
    ))
  encoded
  |> should.equal(
    "[{\"type\":\"to-do\",\"operation\":\"create\",\"attributes\":{\"title\":\"Task\",\"notes\":\"Notes\",\"deadline\":\"2028-02-29\",\"tags\":[\"Work\",\"Errands\"],\"when\":\"today\"}}]",
  )
}

pub fn text_round_trip_preserves_unicode_multiline_and_url_characters_test() {
  let text = "æøå 🦦 é \"quoted\" \\path\nnext\tcolumn\r\n&?=#%+"
  let assert Ok(encoded) =
    payload.create_todo(types.CreateTodoArgs(text, Some(text), None, None, None))
  list.each(["title", "notes"], fn(field) {
    json.parse(
      encoded,
      decode.list(decode.at(["attributes", field], decode.string)),
    )
    |> should.equal(Ok([text]))
  })
}

pub fn clearing_is_distinct_from_omission_test() {
  payload.update_todo(types.UpdateTodoArgs(
    "task-id",
    None,
    Some(""),
    Some("none"),
    Some([]),
  ))
  |> should.equal(Ok(
    "[{\"type\":\"to-do\",\"operation\":\"update\",\"id\":\"task-id\",\"attributes\":{\"notes\":\"\",\"deadline\":\"\",\"tags\":[]}}]",
  ))
  payload.update_todo(types.UpdateTodoArgs("task-id", None, None, None, None))
  |> should.equal(Ok(
    "[{\"type\":\"to-do\",\"operation\":\"update\",\"id\":\"task-id\",\"attributes\":{}}]",
  ))
}

pub fn calendar_validation_checks_leap_years_and_strict_format_test() {
  list.each(["2028-02-29", "2000-02-29", "2026-12-31", "0001-01-01"], fn(date) {
    payload.validate_date(date) |> should.equal(Ok(Nil))
  })
  list.each(
    [
      "2026-02-29", "1900-02-29", "2026-04-31", "2026-00-01", "2026-13-01",
      "2026-01-00", "2026-01-32", "0000-01-01", "2026-1-01", "2026-01-1",
      "2026-01-01T00:00:00Z", "2026-01-01\"", "+026-01-01", "２０２６-01-01", "",
    ],
    fn(date) { payload.validate_date(date) |> should.be_error },
  )
  payload.create_todo(types.CreateTodoArgs(
    "Task",
    None,
    Some("none"),
    None,
    None,
  ))
  |> should.be_error
  payload.update_todo(types.UpdateTodoArgs(
    "task-id",
    None,
    None,
    Some(""),
    None,
  ))
  |> should.be_error
}

pub fn every_update_requires_nonempty_ids_test() {
  payload.complete_todo("") |> should.be_error
  payload.update_todo(types.UpdateTodoArgs("  ", None, None, None, None))
  |> should.be_error
  payload.move_todo("", "Today") |> should.be_error
  payload.move_todo_to_project("task-id", "") |> should.be_error
  payload.move_todo_to_area("task-id", "\n") |> should.be_error
  payload.move_project_to_area("", "area-id") |> should.be_error
}

pub fn project_area_requires_resolved_id_test() {
  let args =
    types.CreateProjectArgs("Project", Some("Notes"), Some("Duplicate name"))
  payload.create_project(args, None) |> should.be_error
  payload.create_project(args, Some("")) |> should.be_error
  payload.create_project(args, Some("area-id"))
  |> should.equal(Ok(
    "[{\"type\":\"project\",\"operation\":\"create\",\"attributes\":{\"title\":\"Project\",\"notes\":\"Notes\",\"area-id\":\"area-id\"}}]",
  ))
}

pub fn container_moves_use_the_correct_destination_fields_test() {
  let assert Ok(to_project) =
    payload.move_todo_to_project("todo-id", "project-id")
  let assert Ok(to_area) = payload.move_todo_to_area("todo-id", "area-id")
  let assert Ok(project_to_area) =
    payload.move_project_to_area("project-id", "area-id")
  json.parse(
    to_project,
    decode.list(decode.at(["attributes", "list-id"], decode.string)),
  )
  |> should.equal(Ok(["project-id"]))
  json.parse(
    to_area,
    decode.list(decode.at(["attributes", "list-id"], decode.string)),
  )
  |> should.equal(Ok(["area-id"]))
  json.parse(
    project_to_area,
    decode.list(decode.at(["attributes", "area-id"], decode.string)),
  )
  |> should.equal(Ok(["area-id"]))
}

pub fn list_mappings_and_fallbacks_are_explicit_test() {
  list.each(
    [#("Today", "today"), #("Anytime", "anytime"), #("Someday", "someday")],
    fn(pair) {
      let #(target, expected) = pair
      let assert Ok(created) =
        payload.create_todo(types.CreateTodoArgs(
          "Task",
          None,
          None,
          None,
          Some(target),
        ))
      let assert Ok(moved) = payload.move_todo("task-id", target)
      list.each([created, moved], fn(encoded) {
        json.parse(
          encoded,
          decode.list(decode.at(["attributes", "when"], decode.string)),
        )
        |> should.equal(Ok([expected]))
      })
    },
  )
  list.each(["Trash", "Logbook", "Inbox", "Upcoming", "anything"], fn(target) {
    payload.move_todo("task-id", target) |> should.be_error
  })
  payload.create_todo(types.CreateTodoArgs(
    "Task",
    None,
    None,
    None,
    Some("Upcoming"),
  ))
  |> should.be_error
}

pub fn completion_is_boolean_and_tags_are_replacement_test() {
  let assert Ok(completed) = payload.complete_todo("task-id")
  json.parse(
    completed,
    decode.list(decode.at(["attributes", "completed"], decode.bool)),
  )
  |> should.equal(Ok([True]))
  let assert Ok(updated) =
    payload.update_todo(types.UpdateTodoArgs(
      "task-id",
      None,
      None,
      None,
      Some(["Unknown", "Work"]),
    ))
  string.contains(updated, "add-tags") |> should.be_false
  json.parse(
    updated,
    decode.list(decode.at(["attributes", "tags"], decode.list(decode.string))),
  )
  |> should.equal(Ok([["Unknown", "Work"]]))
}
