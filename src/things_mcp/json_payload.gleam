//// Pure encoding for the existing Things write tools. Each payload contains
//// exactly one operation; transport, authorization and verification live elsewhere.

import gleam/int
import gleam/json
import gleam/list
import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import things_mcp/types

type ItemKind {
  Todo
  Project
}

type Operation {
  Create
  Update(String)
}

type Attribute {
  Title(String)
  Notes(String)
  Deadline(String)
  Tags(List(String))
  When(String)
  ListId(String)
  AreaId(String)
  Completed
}

pub fn create_todo(args: types.CreateTodoArgs) -> Result(String, String) {
  use deadline <- result.try(deadline(args.due_date, False))
  use when <- result.try(create_when(option.unwrap(args.list, "Inbox")))
  encode(
    Todo,
    Create,
    [Title(args.name)]
      |> optional(args.notes, Notes)
      |> optional(deadline, Deadline)
      |> optional(args.tags, Tags)
      |> optional(when, When),
  )
}

/// The caller resolves the optional area name through the existing AppleScript
/// lookup before dispatch. Names never become JSON destination identifiers.
pub fn create_project(
  args: types.CreateProjectArgs,
  resolved_area_id: Option(String),
) -> Result(String, String) {
  use _ <- result.try(case args.area, resolved_area_id {
    Some(_), None -> Error("The project area must be resolved before writing")
    _, Some(id) -> validate_id(id)
    None, None -> Ok(Nil)
  })
  encode(
    Project,
    Create,
    [Title(args.name)]
      |> optional(args.notes, Notes)
      |> optional(resolved_area_id, AreaId),
  )
}

pub fn update_todo(args: types.UpdateTodoArgs) -> Result(String, String) {
  use due <- result.try(deadline(args.new_due_date, True))
  encode(
    Todo,
    Update(args.id),
    []
      |> optional(args.new_name, Title)
      |> optional(args.new_notes, Notes)
      |> optional(due, Deadline)
      |> optional(args.new_tags, Tags),
  )
}

pub fn complete_todo(id: String) -> Result(String, String) {
  encode(Todo, Update(id), [Completed])
}

/// Trash, Logbook and detach operations use the documented AppleScript fallback.
pub fn move_todo(id: String, target: String) -> Result(String, String) {
  use when <- result.try(case target {
    "Today" -> Ok("today")
    "Anytime" -> Ok("anytime")
    "Someday" -> Ok("someday")
    _ -> Error("This list move requires the AppleScript backend: " <> target)
  })
  encode(Todo, Update(id), [When(when)])
}

pub fn move_todo_to_project(
  id: String,
  project_id: String,
) -> Result(String, String) {
  use _ <- result.try(validate_id(project_id))
  encode(Todo, Update(id), [ListId(project_id)])
}

pub fn move_todo_to_area(
  id: String,
  area_id: String,
) -> Result(String, String) {
  use _ <- result.try(validate_id(area_id))
  encode(Todo, Update(id), [ListId(area_id)])
}

pub fn move_project_to_area(
  id: String,
  area_id: String,
) -> Result(String, String) {
  use _ <- result.try(validate_id(area_id))
  encode(Project, Update(id), [AreaId(area_id)])
}

fn create_when(target: String) -> Result(Option(String), String) {
  case target {
    "Inbox" -> Ok(None)
    "Today" -> Ok(Some("today"))
    "Anytime" -> Ok(Some("anytime"))
    "Someday" -> Ok(Some("someday"))
    _ -> Error("Invalid create list: " <> target)
  }
}

fn optional(
  attrs: List(Attribute),
  value: Option(a),
  attr: fn(a) -> Attribute,
) -> List(Attribute) {
  case value {
    None -> attrs
    Some(value) -> list.append(attrs, [attr(value)])
  }
}

fn deadline(
  value: Option(String),
  allow_clear: Bool,
) -> Result(Option(String), String) {
  case value {
    None -> Ok(None)
    Some("none") if allow_clear -> Ok(Some(""))
    Some(date) -> {
      use _ <- result.try(validate_date(date))
      Ok(Some(date))
    }
  }
}

pub fn validate_id(id: String) -> Result(Nil, String) {
  case string.trim(id) {
    "" -> Error("A nonempty Things ID is required")
    _ -> Ok(Nil)
  }
}

/// Validate calendar dates without converting through UTC or a locale-sensitive
/// parser. The original local YYYY-MM-DD value is sent unchanged.
pub fn validate_date(value: String) -> Result(Nil, String) {
  let valid = case string.split(value, "-") {
    [year, month, day] -> {
      case digits(year, 4), digits(month, 2), digits(day, 2) {
        Ok(y), Ok(m), Ok(d) -> {
          let leap = y % 400 == 0 || { y % 4 == 0 && y % 100 != 0 }
          let max_day = case m {
            2 if leap -> 29
            2 -> 28
            4 | 6 | 9 | 11 -> 30
            _ -> 31
          }
          y >= 1 && m >= 1 && m <= 12 && d >= 1 && d <= max_day
        }
        _, _, _ -> False
      }
    }
    _ -> False
  }
  case valid {
    True -> Ok(Nil)
    False ->
      Error("Invalid date; expected a real calendar date in YYYY-MM-DD format")
  }
}

fn digits(value: String, width: Int) -> Result(Int, Nil) {
  case
    string.length(value) == width
    && list.all(string.to_graphemes(value), fn(c) {
      list.contains(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"], c)
    })
  {
    True -> int.parse(value)
    False -> Error(Nil)
  }
}

fn encode(
  kind: ItemKind,
  operation: Operation,
  attributes: List(Attribute),
) -> Result(String, String) {
  use action <- result.try(case operation {
    Create -> Ok([#("operation", json.string("create"))])
    Update(id) -> {
      use _ <- result.try(validate_id(id))
      Ok([#("operation", json.string("update")), #("id", json.string(id))])
    }
  })
  let kind = case kind {
    Todo -> "to-do"
    Project -> "project"
  }
  Ok(
    json.array(
      [
        json.object(list.append(
          [#("type", json.string(kind))],
          list.append(action, [
            #("attributes", json.object(list.map(attributes, encode_attribute))),
          ]),
        )),
      ],
      fn(item) { item },
    )
    |> json.to_string,
  )
}

fn encode_attribute(attribute: Attribute) -> #(String, json.Json) {
  case attribute {
    Title(value) -> #("title", json.string(value))
    Notes(value) -> #("notes", json.string(value))
    Deadline(value) -> #("deadline", json.string(value))
    Tags(value) -> #("tags", json.array(value, json.string))
    When(value) -> #("when", json.string(value))
    ListId(value) -> #("list-id", json.string(value))
    AreaId(value) -> #("area-id", json.string(value))
    Completed -> #("completed", json.bool(True))
  }
}
