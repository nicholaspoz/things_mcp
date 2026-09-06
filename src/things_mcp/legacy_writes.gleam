//// Compatibility writes for operations the public JSON interface cannot reproduce.
//// Select this backend before dispatch; never use it to retry uncertain JSON writes.

import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import things_mcp/applescript
import things_mcp/json_payload
import things_mcp/json_transport
import things_mcp/types

pub fn handle_create_todo(
  args: types.CreateTodoArgs,
) -> Result(String, String) {
  use date_script <- result.try(case args.due_date {
    None -> Ok("")
    Some(date) -> calendar_date_script(date)
  })
  // Build properties list
  let props = [#("name", applescript.quote_string(args.name))]

  // Add optional properties
  let props = case args.notes {
    Some(notes) ->
      list.append(props, [#("notes", applescript.quote_string(notes))])
    None -> props
  }

  let props = case args.due_date {
    Some(_) -> list.append(props, [#("due date", "requestedDate")])
    None -> props
  }

  let props = case args.tags {
    Some(tags) -> {
      let tag_string = string.join(tags, ", ")
      list.append(props, [#("tag names", applescript.quote_string(tag_string))])
    }
    None -> props
  }

  let properties = applescript.build_properties(props)
  let target_list = option.unwrap(args.list, "Inbox")

  // Build and execute AppleScript command
  let command =
    date_script
    <> "set newToDo to make new to do in list \""
    <> target_list
    <> "\" with properties "
    <> properties
    <> case target_list {
      "Inbox" -> ""
      _ -> "\nmove newToDo to list " <> applescript.quote_string(target_list)
    }
    <> "\nreturn id of newToDo"

  execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    "Created todo: " <> args.name <> "\nID: " <> output
  })
}

pub fn handle_complete_todo(
  args: types.CompleteTodoArgs,
) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.id)
  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nset status of targetToDo to completed"

  execute(applescript.tell_things(command))
  |> result.map(fn(_output) { "Completed todo: " <> args.id })
}

pub fn handle_update_todo(
  args: types.UpdateTodoArgs,
) -> Result(String, String) {
  use date_script <- result.try(case args.new_due_date {
    None | Some("none") -> Ok("")
    Some(date) -> calendar_date_script(date)
  })
  let todo_ref = applescript.todo_by_id(args.id)

  // Build list of update commands
  let commands = ["set targetToDo to " <> todo_ref]

  let commands = case args.new_name {
    Some(new_name) ->
      list.append(commands, [
        "set name of targetToDo to " <> applescript.quote_string(new_name),
      ])
    None -> commands
  }

  let commands = case args.new_notes {
    Some(new_notes) ->
      list.append(commands, [
        "set notes of targetToDo to " <> applescript.quote_string(new_notes),
      ])
    None -> commands
  }

  let commands = case args.new_due_date {
    Some("none") ->
      // Assigning missing value or an empty string fails date coercion (-1700).
      // Deleting the property clears the deadline without deleting the item.
      list.append(commands, ["delete due date of targetToDo"])
    Some(_) ->
      list.append(commands, [
        date_script <> "set due date of targetToDo to requestedDate",
      ])
    None -> commands
  }

  let commands = case args.new_tags {
    Some(tags) -> {
      let tag_string = string.join(tags, ", ")
      list.append(commands, [
        "set tag names of targetToDo to "
        <> applescript.quote_string(tag_string),
      ])
    }
    None -> commands
  }

  // Execute all update commands
  let command = string.join(commands, "\n")

  execute(applescript.tell_things(command))
  |> result.map(fn(_output) { "Updated todo: " <> args.id })
}

pub fn handle_create_project(
  args: types.CreateProjectArgs,
) -> Result(String, String) {
  // Build properties list
  let props = [#("name", applescript.quote_string(args.name))]

  // Add optional properties
  let props = case args.notes {
    Some(notes) ->
      list.append(props, [#("notes", applescript.quote_string(notes))])
    None -> props
  }

  let props = case args.area {
    Some(area) ->
      list.append(props, [#("area", "area " <> applescript.quote_string(area))])
    None -> props
  }

  let properties = applescript.build_properties(props)

  // Build and execute AppleScript command
  let command =
    "set newProject to make new project with properties "
    <> properties
    <> "\nreturn id of newProject"

  execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    "Created project: " <> args.name <> "\nID: " <> output
  })
}

pub fn handle_move_todo(args: types.MoveTodoArgs) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.id)

  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nmove targetToDo to list "
    <> applescript.quote_string(args.list)

  execute(applescript.tell_things(command))
  |> result.map(fn(_output) { "Moved todo " <> args.id <> " to " <> args.list })
}

pub fn handle_remove_todo_from_project(
  args: types.RemoveTodoFromProjectArgs,
) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.id)
  let command =
    "set targetToDo to " <> todo_ref <> "\ndelete project of targetToDo"

  execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Removed todo " <> args.id <> " from its project"
  })
}

pub fn handle_remove_project_from_area(
  args: types.RemoveProjectFromAreaArgs,
) -> Result(String, String) {
  let project_ref = applescript.project_by_id(args.id)
  let command =
    "set targetProject to " <> project_ref <> "\ndelete area of targetProject"

  execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Removed project " <> args.id <> " from its area"
  })
}

fn execute(script: String) -> Result(String, String) {
  json_transport.run("/usr/bin/osascript", ["-e", script], 10_000)
  |> result.map_error(fn(_) {
    "AppleScript compatibility write failed or timed out; completion may be uncertain; do not retry automatically"
  })
}

// AppleScript's date-string parser depends on locale and can reinterpret ISO
// input. Construct the local calendar date explicitly, with a safe day first.
fn calendar_date_script(value: String) -> Result(String, String) {
  use _ <- result.try(json_payload.validate_date(value))
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
