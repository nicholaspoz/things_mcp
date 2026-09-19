//// Supported AppleScript reads used only to verify synchronous write completion.
//// User values are arguments, never AppleScript source.

import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import things_mcp/applescript
import things_mcp/types

pub type Kind {
  Todo
  Project
}

type Unit {
  Millisecond
}

@external(erlang, "erlang", "monotonic_time")
fn now(unit: Unit) -> Int

type Lookup {
  Item
  ListOnly
}

type Check {
  Equal(String, String)
  Missing(String)
  InList(String)
  DueDate(String)
  Tags(List(String))
}

pub fn status(kind: Kind, id: String) -> Result(String, String) {
  read(kind, id, "return status of targetItem as string", [], 5000, Item, False)
  |> result.map(string.trim)
}

pub fn verify_status(
  kind: Kind,
  id: String,
  expected: String,
) -> Result(Nil, String) {
  verify(kind, id, [Equal("status as string", expected)])
}

pub fn verify_detached(kind: Kind, id: String) -> Result(Nil, String) {
  verify(kind, id, [
    Missing(case kind {
      Todo -> "project"
      Project -> "area"
    }),
  ])
}

pub fn area_id_by_name(name: String) -> Result(String, String) {
  run("return id of area (item 1 of argv)", [name], 5000)
  |> result.map(string.trim)
}

pub fn verify_todo_create(
  id: String,
  args: types.CreateTodoArgs,
) -> Result(Nil, String) {
  verify(
    Todo,
    id,
    [Equal("name", args.name), InList(option.unwrap(args.list, "Inbox"))]
      |> optional(args.notes, fn(value) { Equal("notes", value) })
      |> optional(args.due_date, DueDate)
      |> optional(args.tags, Tags),
  )
}

pub fn verify_project_create(
  id: String,
  args: types.CreateProjectArgs,
  area: Option(String),
) -> Result(Nil, String) {
  let checks =
    [Equal("name", args.name)]
    |> optional(args.notes, fn(value) { Equal("notes", value) })
  let checks = case area {
    Some(id) -> list.append(checks, [Equal("id of area", id)])
    None -> list.append(checks, [Missing("area")])
  }
  verify(Project, id, checks)
}

pub fn verify_todo_update(
  id: String,
  args: types.UpdateTodoArgs,
) -> Result(Nil, String) {
  let checks =
    []
    |> optional(args.new_name, fn(value) { Equal("name", value) })
    |> optional(args.new_notes, fn(value) { Equal("notes", value) })
    |> optional(args.new_tags, Tags)
  let checks = case args.new_due_date {
    None -> checks
    Some("none") -> list.append(checks, [Missing("due date")])
    Some(value) -> list.append(checks, [DueDate(value)])
  }
  verify(Todo, id, checks)
}

pub fn verify_completed(id: String) -> Result(Nil, String) {
  verify(Todo, id, [Equal("status as string", "completed")])
}

pub fn verify_project_completed(id: String) -> Result(Nil, String) {
  verify(Project, id, [Equal("status as string", "completed")])
}

pub fn verify_list(id: String, target: String) -> Result(Nil, String) {
  verify(Todo, id, [InList(target)])
}

pub fn verify_project(id: String, project_id: String) -> Result(Nil, String) {
  verify(Todo, id, [Equal("id of project", project_id)])
}

pub fn verify_area(
  kind: Kind,
  id: String,
  area_id: String,
) -> Result(Nil, String) {
  let checks = [Equal("id of area", area_id)]
  verify(kind, id, case kind {
    Todo -> list.append(checks, [Missing("project")])
    Project -> checks
  })
}

fn optional(
  checks: List(Check),
  value: Option(a),
  make: fn(a) -> Check,
) -> List(Check) {
  case value {
    None -> checks
    Some(value) -> list.append(checks, [make(value)])
  }
}

fn verify(kind: Kind, id: String, checks: List(Check)) -> Result(Nil, String) {
  let #(lines, args) = list.fold(checks, #([], []), build_check)
  let body = string.join(list.append(lines, ["return \"verified\""]), "\n")
  // List membership is checked through the list itself, including Trash.
  let lookup = case
    list.any(checks, fn(check) {
      case check {
        InList(_) -> False
        _ -> True
      }
    })
  {
    True -> Item
    False -> ListOnly
  }
  poll(kind, id, body, args, lookup, now(Millisecond) + 3000)
  |> result.map_error(fn(error) {
    "Things reported success but verification failed for ID: "
    <> id
    <> "; completion is uncertain; do not retry automatically: "
    <> error
  })
}

fn poll(
  kind: Kind,
  id: String,
  body: String,
  args: List(String),
  lookup: Lookup,
  deadline: Int,
) -> Result(Nil, String) {
  let remaining = deadline - now(Millisecond)
  case remaining <= 0 {
    True ->
      Error(
        "Things write verification timed out; completion is uncertain; do not retry automatically",
      )
    False -> {
      use output <- result.try(read(
        kind,
        id,
        body,
        args,
        remaining,
        lookup,
        True,
      ))
      case string.trim(output) {
        "verified" -> Ok(Nil)
        "pending" -> {
          applescript.sleep(int.min(
            100,
            int.max(0, deadline - now(Millisecond)),
          ))
          poll(kind, id, body, args, lookup, deadline)
        }
        _ ->
          Error(
            "Unexpected Things write verification result; completion is uncertain",
          )
      }
    }
  }
}

fn read(
  kind: Kind,
  id: String,
  body: String,
  args: List(String),
  timeout: Int,
  lookup: Lookup,
  wait_for_visibility: Bool,
) -> Result(String, String) {
  let kind = case kind {
    Todo -> "to do"
    Project -> "project"
  }
  // List membership checks must also work for Trash, whose items are absent
  // from Things' application-level collection.
  let lookup = case lookup {
    Item -> {
      let target = kind <> " id (item 1 of argv)"
      let visibility = case wait_for_visibility {
        True -> "if not (exists (" <> target <> ")) then return \"pending\"\n"
        False -> ""
      }
      visibility <> "set targetItem to " <> target <> "\n"
    }
    ListOnly -> ""
  }
  run(lookup <> body, [id, ..args], timeout)
}

fn run(
  body: String,
  args: List(String),
  timeout: Int,
) -> Result(String, String) {
  let script =
    "on run argv\ntell application \"Things3\"\nconsidering case\n"
    <> body
    <> "\nend considering\nend tell\nend run"
  applescript.run("/usr/bin/osascript", ["-e", script, "--", ..args], timeout)
}

fn argument(args: List(String), value: String) -> #(String, List(String)) {
  // Argument 1 is always the stable item ID.
  #(
    "(item " <> int.to_string(list.length(args) + 2) <> " of argv)",
    list.append(args, [value]),
  )
}

fn condition(predicate: String) -> String {
  "if not (" <> predicate <> ") then return \"pending\""
}

fn build_check(
  state: #(List(String), List(String)),
  check: Check,
) -> #(List(String), List(String)) {
  let #(lines, args) = state
  let #(new_lines, args) = case check {
    Equal(property, value) -> {
      let #(arg, args) = argument(args, value)
      let expression = case property {
        "status as string" -> "(status of targetItem as string)"
        _ -> "(" <> property <> " of targetItem)"
      }
      #([condition(expression <> " is equal to " <> arg)], args)
    }
    Missing(property) -> #(
      [condition(property <> " of targetItem is missing value")],
      args,
    )
    InList(value) -> {
      let #(arg, args) = argument(args, value)
      #(
        [
          condition(
            "exists (first to do of list "
            <> arg
            <> " whose id is (item 1 of argv))",
          ),
        ],
        args,
      )
    }
    DueDate(value) -> {
      let parts = string.split(value, "-")
      case parts {
        [year, month, day] -> {
          let #(year_arg, args) = argument(args, year)
          let #(month_arg, args) = argument(args, month)
          let #(day_arg, args) = argument(args, day)
          #(
            [
              "set actualDate to due date of targetItem",
              condition("actualDate is not missing value"),
              condition(
                "(year of actualDate as integer) = ("
                <> year_arg
                <> " as integer)",
              ),
              condition(
                "(month of actualDate as integer) = ("
                <> month_arg
                <> " as integer)",
              ),
              condition(
                "(day of actualDate as integer) = ("
                <> day_arg
                <> " as integer)",
              ),
            ],
            args,
          )
        }
        _ -> #(["error \"Invalid expected deadline\""], args)
      }
    }
    Tags(values) -> {
      // Split/trim like Things' comma-separated tag names setter. Resolve the
      // expected set using AppleScript's own case-insensitive comparisons, so
      // canonical mixed-case names and repeated variants count only once.
      let tags =
        values
        |> list.flat_map(fn(value) { string.split(value, ",") })
        |> list.map(string.trim)
        |> list.filter(fn(value) { value != "" })
      let #(args, tag_args) =
        list.map_fold(tags, args, fn(args, value) {
          let #(arg, args) = argument(args, value)
          #(args, arg)
        })
      #(
        [
          "ignoring case",
          "set expectedTags to {}",
          "repeat with expectedTag in {" <> string.join(tag_args, ", ") <> "}",
          "if expectedTags does not contain (contents of expectedTag) then set end of expectedTags to contents of expectedTag",
          "end repeat",
          "set actualTags to name of every tag of targetItem",
          condition("(count of actualTags) = (count of expectedTags)"),
          "repeat with expectedTag in expectedTags",
          condition("actualTags contains (contents of expectedTag)"),
          "end repeat",
          "end ignoring",
        ],
        args,
      )
    }
  }
  #(list.append(lines, new_lines), args)
}

/// Preserve lifecycle status when changing fields or containers. Writes are never retried.
pub fn preserving_status(
  kind: Kind,
  id: String,
  command: String,
  verify_change: fn() -> Result(Nil, String),
) -> Result(Nil, String) {
  use before <- result.try(status(kind, id))
  use _ <- result.try(
    applescript.execute_write(applescript.tell_things(command)),
  )
  use _ <- result.try(verify_change())
  verify_status(kind, id, before)
}

/// A known created ID must survive subsequent move/read-back errors.
pub fn created(id: String, outcome: Result(a, String)) -> Result(a, String) {
  result.map_error(outcome, fn(error) { error <> "\nCreated ID: " <> id })
}
