//// Live parity coverage. Every fixture belongs to one UUID-scoped namespace;
//// cleanup runs before assertions, including when a handler returns an error.
//// Run independently with `gleam run -m json_write_parity_test`.

import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import gleeunit/should
import things_mcp/json_transport
import things_mcp/tools/move_ops
import things_mcp/tools/project_ops
import things_mcp/tools/todo_ops
import things_mcp/types
import things_mcp/write_checks

pub fn main() {
  lists_text_and_duplicate_ids_test()
  updates_clear_fields_and_complete_test()
  disposable_container_moves_and_detach_test()
  tag_and_note_limit_fallback_test()
}

pub fn lists_text_and_duplicate_ids_test() {
  scoped("lists and text", lists_text_and_duplicates)
}

pub fn updates_clear_fields_and_complete_test() {
  scoped("updates and completion", updates_and_completion)
}

pub fn disposable_container_moves_and_detach_test() {
  scoped("containers and detach", containers_and_detach)
}

pub fn tag_and_note_limit_fallback_test() {
  scoped("fallback boundaries", fallback_boundaries)
}

fn scoped(label: String, body: fn(String) -> Result(Nil, String)) {
  let assert Ok(uuid) = json_transport.run("/usr/bin/uuidgen", [], 5000)
  let prefix = "__TEST_JSON_" <> string.trim(uuid) <> "_"
  io.println("JSON parity: " <> label <> " (" <> prefix <> ")")
  let outcome = body(prefix)
  let cleanup_outcome = cleanup(prefix)
  // Do not panic before the cleanup above has had a chance to run.
  case outcome {
    Error(message) -> io.println("Parity failure: " <> message)
    Ok(_) -> Nil
  }
  case cleanup_outcome {
    Error(message) -> io.println("Cleanup failure: " <> message)
    Ok(_) -> Nil
  }
  outcome |> should.be_ok
  cleanup_outcome |> should.be_ok
}

fn lists_text_and_duplicates(prefix: String) -> Result(Nil, String) {
  use _ <- result.try(
    list.try_each(["Inbox", "Today", "Anytime", "Someday"], fn(target) {
      use id <- result.try(
        create_todo(types.CreateTodoArgs(
          prefix <> target,
          None,
          None,
          None,
          Some(target),
        )),
      )
      exact(
        "return (item 1 of argv) is in (id of every to do of list (item 2 of argv))",
        [id, target],
        "creation appears immediately in " <> target,
      )
    }),
  )
  let name = prefix <> "æøå 🦦 quoted \"title\" \\ path"
  let notes = "first æøå 🦦 é\nsecond \"quoted\" \\path\tcolumn\n&?=#%+\n"
  use first <- result.try(
    create_todo(types.CreateTodoArgs(name, Some(notes), None, None, None)),
  )
  use second <- result.try(
    create_todo(types.CreateTodoArgs(
      name,
      Some("different notes"),
      None,
      None,
      None,
    )),
  )
  use _ <- result.try(check(first != second, "duplicate names returned same ID"))
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nreturn (name of t is (item 2 of argv)) and (notes of t is (item 3 of argv))",
    [first, name, notes],
    "Unicode, punctuation, backslash, and multiline text round-trip",
  ))
  use _ <- result.try(exact(
    "return notes of (to do id (item 1 of argv)) is (item 2 of argv)",
    [second, "different notes"],
    "second duplicate is independently addressable",
  ))
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      first,
      None,
      Some("first only"),
      None,
      None,
    )),
  )
  exact(
    "return notes of (to do id (item 1 of argv)) is (item 2 of argv)",
    [second, "different notes"],
    "updating duplicate by ID preserves its sibling",
  )
}

fn updates_and_completion(prefix: String) -> Result(Nil, String) {
  let tag = prefix <> "known-tag"
  use _ <- result.try(
    run(
      "make new tag with properties {name:(item 1 of argv)}\nreturn \"created\"",
      [tag],
    ),
  )
  let name = prefix <> "update"
  use id <- result.try(
    create_todo(types.CreateTodoArgs(
      name,
      Some("keep notes"),
      Some("2028-02-29"),
      Some([tag]),
      Some("Anytime"),
    )),
  )
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      id,
      Some(name <> " renamed"),
      None,
      None,
      None,
    )),
  )
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nset d to due date of t\nreturn (notes of t is \"keep notes\") and ((name of every tag of t) is {(item 2 of argv)}) and (year of d is 2028) and ((month of d as integer) is 2) and (day of d is 29)",
    [id, tag],
    "omitted notes, tags, and local leap-day deadline survive update",
  ))
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      id,
      None,
      Some("new\nnotes \\"),
      Some("2029-01-01"),
      None,
    )),
  )
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nset d to due date of t\nreturn (notes of t is (item 2 of argv)) and (year of d is 2029) and ((month of d as integer) is 1) and (day of d is 1)",
    [id, "new\nnotes \\"],
    "notes and calendar date updated exactly",
  ))
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      id,
      None,
      Some(""),
      None,
      Some([]),
    )),
  )
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nset d to due date of t\nreturn (notes of t is \"\") and ((count of tags of t) is 0) and (year of d is 2029) and ((month of d as integer) is 1) and (day of d is 1)",
    [id],
    "JSON-only empty notes and tags clear without changing deadline",
  ))
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      id,
      None,
      None,
      Some("none"),
      None,
    )),
  )
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nreturn (notes of t is \"\") and (due date of t is missing value) and ((count of tags of t) is 0) and (name of t is (item 2 of argv))",
    [id, name <> " renamed"],
    "explicit clears preserve omitted title",
  ))
  use _ <- result.try(todo_ops.handle_complete_todo(types.CompleteTodoArgs(id)))
  use _ <- result.try(exact(
    "return status of (to do id (item 1 of argv)) is completed",
    [id],
    "complete returns only after completed status is visible",
  ))
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      id,
      None,
      Some("edited after completion"),
      None,
      None,
    )),
  )
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nreturn (status of t is completed) and (notes of t is \"edited after completion\")",
    [id],
    "JSON notes update preserves completed status",
  ))
  use canceled_id <- result.try(
    create_todo(types.CreateTodoArgs(
      prefix <> "canceled status",
      None,
      None,
      None,
      Some("Anytime"),
    )),
  )
  use _ <- result.try(
    run(
      "set status of (to do id (item 1 of argv)) to canceled\nreturn \"canceled\"",
      [canceled_id],
    ),
  )
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      canceled_id,
      None,
      Some("edited after cancellation"),
      None,
      None,
    )),
  )
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nreturn (status of t is canceled) and (notes of t is \"edited after cancellation\")",
    [canceled_id],
    "JSON notes update preserves canceled status",
  ))
  use _ <- result.try(expect_error(
    todo_ops.handle_complete_todo(types.CompleteTodoArgs(prefix <> "missing")),
    "complete missing ID",
  ))
  use _ <- result.try(expect_error(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      prefix <> "missing",
      None,
      Some("x"),
      None,
      None,
    )),
    "update missing ID",
  ))
  expect_error(
    move_ops.handle_move_todo_to_project(types.MoveTodoToProjectArgs(
      id,
      prefix <> "missing",
    )),
    "move to missing destination",
  )
}

fn containers_and_detach(prefix: String) -> Result(Nil, String) {
  let area_name = prefix <> "area"
  use area <- result.try(
    run(
      "set a to make new area with properties {name:(item 1 of argv)}\nreturn id of a",
      [area_name],
    ),
  )
  let area = string.trim(area)
  use project <- result.try(
    create_project(types.CreateProjectArgs(
      prefix <> "project",
      Some("project notes"),
      None,
    )),
  )
  use area_project <- result.try(
    create_project(types.CreateProjectArgs(
      prefix <> "created in area",
      Some("æøå\nproject \\"),
      Some(area_name),
    )),
  )
  use _ <- result.try(write_checks.verify_area(
    write_checks.Project,
    area_project,
    area,
  ))
  use todo_id <- result.try(
    create_todo(types.CreateTodoArgs(prefix <> "member", None, None, None, None)),
  )
  use _ <- result.try(
    move_ops.handle_move_todo_to_project(types.MoveTodoToProjectArgs(
      todo_id,
      project,
    )),
  )
  use _ <- result.try(write_checks.verify_project(todo_id, project))
  use _ <- result.try(
    move_ops.handle_remove_todo_from_project(types.RemoveTodoFromProjectArgs(
      todo_id,
    ))
    |> result.map_error(fn(error) { "Detach task: " <> error }),
  )
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nreturn (project of t is missing value) and (exists (project id (item 2 of argv)))",
    [todo_id, project],
    "detaching a task preserves its project",
  ))
  use _ <- result.try(
    move_ops.handle_move_todo_to_project(types.MoveTodoToProjectArgs(
      todo_id,
      project,
    )),
  )
  use _ <- result.try(
    move_ops.handle_move_todo_to_area(types.MoveTodoToAreaArgs(todo_id, area)),
  )
  use _ <- result.try(exact(
    "set t to to do id (item 1 of argv)\nreturn (project of t is missing value) and (id of area of t is (item 2 of argv)) and (exists (project id (item 3 of argv)))",
    [todo_id, area, project],
    "moving project task to area removes membership and preserves project",
  ))
  use _ <- result.try(
    move_ops.handle_move_project_to_area(types.MoveProjectToAreaArgs(
      project,
      area,
    )),
  )
  use _ <- result.try(write_checks.verify_area(
    write_checks.Project,
    project,
    area,
  ))
  use _ <- result.try(
    move_ops.handle_remove_project_from_area(types.RemoveProjectFromAreaArgs(
      project,
    ))
    |> result.map_error(fn(error) { "Detach project: " <> error }),
  )
  use _ <- result.try(exact(
    "set p to project id (item 1 of argv)\nreturn (area of p is missing value) and (exists (area id (item 2 of argv))) and (exists (project id (item 3 of argv)))",
    [project, area, area_project],
    "detaching project preserves its area and sibling project",
  ))
  use _ <- result.try(
    list.try_each(["Today", "Someday", "Anytime"], fn(target) {
      use _ <- result.try(
        move_ops.handle_move_todo(types.MoveTodoArgs(todo_id, target))
        |> result.map_error(fn(error) { "Move to " <> target <> ": " <> error }),
      )
      exact(
        "return (item 1 of argv) is in (id of every to do of list (item 2 of argv))",
        [todo_id, target],
        "move appears immediately in " <> target,
      )
    }),
  )
  // The existing AppleScript move rejects open items with error 301. Moving to
  // Logbook must not silently complete an item on the caller's behalf.
  use _ <- result.try(expect_error(
    move_ops.handle_move_todo(types.MoveTodoArgs(todo_id, "Logbook")),
    "moving an open task to Logbook is rejected",
  ))
  use _ <- result.try(exact(
    "return (status of (to do id (item 1 of argv)) is open) and ((item 1 of argv) is in (id of every to do of list \"Anytime\"))",
    [todo_id],
    "rejected Logbook move preserves status and list",
  ))
  use _ <- result.try(
    todo_ops.handle_complete_todo(types.CompleteTodoArgs(todo_id)),
  )
  // The original direct AppleScript command also rejects completed items on
  // this installation. Do not use the global logging command to force success.
  use _ <- result.try(expect_error(
    move_ops.handle_move_todo(types.MoveTodoArgs(todo_id, "Logbook")),
    "moving a completed task to Logbook preserves the legacy rejection",
  ))
  use _ <- result.try(exact(
    "return status of (to do id (item 1 of argv)) is completed",
    [todo_id],
    "rejected Logbook move preserves completed status",
  ))
  use _ <- result.try(
    move_ops.handle_move_todo(types.MoveTodoArgs(todo_id, "Trash")),
  )
  exact(
    "return (item 1 of argv) is in (id of every to do of list \"Trash\")",
    [todo_id],
    "completed task moves immediately to Trash",
  )
}

fn fallback_boundaries(prefix: String) -> Result(Nil, String) {
  let tag = prefix <> "unknown-tag"
  use _ <- result.try(exact(
    "return not (exists (first tag whose name is (item 1 of argv)))",
    [tag],
    "fallback tag starts absent",
  ))
  use tagged <- result.try(
    create_todo(types.CreateTodoArgs(
      prefix <> "unknown tag",
      None,
      None,
      Some([tag]),
      None,
    )),
  )
  use _ <- result.try(exact(
    "return (name of every tag of (to do id (item 1 of argv))) is {(item 2 of argv)}",
    [tagged, tag],
    "unknown tag created and applied through fallback",
  ))
  let other_tag = prefix <> "unknown-update-tag"
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      tagged,
      None,
      None,
      None,
      Some([other_tag]),
    )),
  )
  use _ <- result.try(exact(
    "return (name of every tag of (to do id (item 1 of argv))) is {(item 2 of argv)}",
    [tagged, other_tag],
    "unknown update tag replaces previous tag",
  ))
  let at_limit = string.repeat("a", 10_000)
  let over_limit = at_limit <> "z"
  use normal <- result.try(
    create_todo(types.CreateTodoArgs(
      prefix <> "10000 notes",
      Some(at_limit),
      None,
      None,
      None,
    )),
  )
  use large <- result.try(
    create_todo(types.CreateTodoArgs(
      prefix <> "10001 notes",
      Some(over_limit),
      None,
      None,
      None,
    )),
  )
  use _ <- result.try(exact(
    "return notes of (to do id (item 1 of argv)) is (item 2 of argv)",
    [normal, at_limit],
    "10000-character JSON notes preserved",
  ))
  use _ <- result.try(exact(
    "return notes of (to do id (item 1 of argv)) is (item 2 of argv)",
    [large, over_limit],
    "10001-character fallback notes preserved",
  ))
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      normal,
      None,
      Some(over_limit),
      None,
      None,
    )),
  )
  use _ <- result.try(exact(
    "return notes of (to do id (item 1 of argv)) is (item 2 of argv)",
    [normal, over_limit],
    "over-limit update notes preserved",
  ))
  use project <- result.try(
    create_project(types.CreateProjectArgs(
      prefix <> "large project notes",
      Some(over_limit),
      None,
    )),
  )
  exact(
    "return notes of (project id (item 1 of argv)) is (item 2 of argv)",
    [project, over_limit],
    "over-limit project notes preserved",
  )
}

fn create_todo(args: types.CreateTodoArgs) -> Result(String, String) {
  use output <- result.try(todo_ops.handle_create_todo(args))
  created_id(output)
}

fn create_project(args: types.CreateProjectArgs) -> Result(String, String) {
  use output <- result.try(project_ops.handle_create_project(args))
  created_id(output)
}

fn created_id(output: String) -> Result(String, String) {
  case string.split_once(output, "\nID: ") {
    Ok(#(_, id)) if id != "" -> Ok(string.trim(id))
    _ -> Error("Handler create response omitted its ID")
  }
}

fn run(body: String, args: List(String)) -> Result(String, String) {
  let script =
    "on run argv\nconsidering case\ntell application \"Things3\"\n"
    <> body
    <> "\nend tell\nend considering\nend run"
  json_transport.run("/usr/bin/osascript", ["-e", script, "--", ..args], 10_000)
}

fn exact(
  body: String,
  args: List(String),
  label: String,
) -> Result(Nil, String) {
  use output <- result.try(run(body, args))
  check(string.trim(output) == "true", label)
}

fn check(condition: Bool, label: String) -> Result(Nil, String) {
  case condition {
    True -> Ok(Nil)
    False -> Error(label)
  }
}

fn expect_error(
  outcome: Result(a, String),
  label: String,
) -> Result(Nil, String) {
  case outcome {
    Error(_) -> Ok(Nil)
    Ok(_) -> Error(label <> " unexpectedly succeeded")
  }
}

fn cleanup(prefix: String) -> Result(Nil, String) {
  run(
    "set fixturePrefix to item 1 of argv
set fixtureTodos to {}
repeat with listName in {\"Inbox\", \"Today\", \"Anytime\", \"Someday\", \"Upcoming\", \"Logbook\"}
set fixtureNames to name of every to do of list (contents of listName)
set fixtureIDs to id of every to do of list (contents of listName)
repeat with i from 1 to count of fixtureNames
if item i of fixtureNames starts with fixturePrefix then
set fixtureID to item i of fixtureIDs
if fixtureID is not in fixtureTodos then set end of fixtureTodos to fixtureID
end if
end repeat
end repeat
repeat with fixtureID in fixtureTodos
move (to do id (contents of fixtureID)) to list \"Trash\"
end repeat
set fixtureProjects to {}
set fixtureNames to name of every project
set fixtureIDs to id of every project
repeat with i from 1 to count of fixtureNames
if item i of fixtureNames starts with fixturePrefix then set end of fixtureProjects to item i of fixtureIDs
end repeat
repeat with fixtureID in fixtureProjects
move (project id (contents of fixtureID)) to list \"Trash\"
end repeat
set fixtureAreas to {}
set fixtureNames to name of every area
set fixtureIDs to id of every area
repeat with i from 1 to count of fixtureNames
if item i of fixtureNames starts with fixturePrefix then set end of fixtureAreas to item i of fixtureIDs
end repeat
repeat with fixtureID in fixtureAreas
delete (area id (contents of fixtureID))
end repeat
set fixtureTags to {}
set fixtureNames to name of every tag
set fixtureIDs to id of every tag
repeat with i from 1 to count of fixtureNames
if item i of fixtureNames starts with fixturePrefix then set end of fixtureTags to item i of fixtureIDs
end repeat
repeat with fixtureID in fixtureTags
delete (tag id (contents of fixtureID))
end repeat
repeat with listName in {\"Inbox\", \"Today\", \"Anytime\", \"Someday\", \"Upcoming\", \"Logbook\"}
set remainingNames to get name of every to do of list (contents of listName)
repeat with fixtureName in remainingNames
if (contents of fixtureName) starts with fixturePrefix then error \"Fixture task remains after cleanup\"
end repeat
end repeat
set remainingNames to get name of every area
repeat with fixtureName in remainingNames
if (contents of fixtureName) starts with fixturePrefix then error \"Fixture area remains after cleanup\"
end repeat
set remainingNames to get name of every tag
repeat with fixtureName in remainingNames
if (contents of fixtureName) starts with fixturePrefix then error \"Fixture tag remains after cleanup\"
end repeat
return \"cleaned\"",
    [prefix],
  )
  |> result.map(fn(_) { Nil })
}
