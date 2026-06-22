import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import things_mcp/applescript
import things_mcp/types

// ===== CREATE TODO =====

pub fn handle_create_todo(
  args: types.CreateTodoArgs,
) -> Result(String, String) {
  // Build properties list
  let props = [#("name", applescript.quote_string(args.name))]

  // Add optional properties
  let props = case args.notes {
    Some(notes) ->
      list.append(props, [#("notes", applescript.quote_string(notes))])
    None -> props
  }

  let props = case args.due_date {
    Some(date) -> list.append(props, [#("due date", "date \"" <> date <> "\"")])
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
    "set newToDo to make new to do in list \""
    <> target_list
    <> "\" with properties "
    <> properties
    <> "\nreturn id of newToDo"

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    "Created todo: " <> args.name <> "\nID: " <> output
  })
}

// ===== LIST TODOS =====

pub fn handle_list_todos(args: types.ListTodosArgs) -> Result(String, String) {
  let location = option.unwrap(args.location, "Today")
  let status_filter = option.unwrap(args.status, "open")

  // Build AppleScript to get todos with properties
  let command = "
    set todoList to {}
    set theList to list \"" <> location <> "\"
    repeat with todo in to dos of theList
      try
        set todoName to name of todo
        set todoID to id of todo
        set todoStatus to status of todo as string
        set todoNotes to notes of todo
        set todoDueDate to \"\"
        try
          set todoDueDate to due date of todo as string
        end try
        set todoTags to tag names of todo as string
        set todoInfo to todoID & \" | \" & todoName & \" | \" & todoStatus & \" | \" & todoNotes & \" | \" & todoDueDate & \" | \" & todoTags
        set end of todoList to todoInfo
      end try
    end repeat
    set AppleScript's text item delimiters to linefeed
    set todoOutput to todoList as text
    set AppleScript's text item delimiters to \"\"
    return todoOutput
  "

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    let filtered = filter_by_status(output, status_filter)
    "Todos in " <> location <> ":\n" <> filtered
  })
}

fn filter_by_status(output: String, status: String) -> String {
  case status {
    "all" -> output
    "open" ->
      output
      |> string.split("\n")
      |> list.filter(fn(line) { string.contains(line, "| open |") })
      |> string.join("\n")
    "completed" ->
      output
      |> string.split("\n")
      |> list.filter(fn(line) { string.contains(line, "| completed |") })
      |> string.join("\n")
    _ -> output
  }
}

// ===== GET TODO =====

pub fn handle_get_todo(args: types.GetTodoArgs) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.id)
  let command = "
    set targetToDo to " <> todo_ref <> "
    set todoName to name of targetToDo
    set todoID to id of targetToDo
    set todoStatus to status of targetToDo as string
    set todoNotes to notes of targetToDo
    set todoDueDate to \"\"
    try
      set todoDueDate to due date of targetToDo as string
    end try
    set todoTags to tag names of targetToDo as string
    return \"ID: \" & todoID & linefeed & \"Name: \" & todoName & linefeed & \"Status: \" & todoStatus & linefeed & \"Notes:\" & linefeed & todoNotes & linefeed & \"Due date: \" & todoDueDate & linefeed & \"Tags: \" & todoTags
  "

  applescript.execute(applescript.tell_things(command))
}

// ===== COMPLETE TODO =====

pub fn handle_complete_todo(
  args: types.CompleteTodoArgs,
) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.id)
  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nset status of targetToDo to completed"

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) { "Completed todo: " <> args.id })
}

// ===== UPDATE TODO =====

pub fn handle_update_todo(
  args: types.UpdateTodoArgs,
) -> Result(String, String) {
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
      list.append(commands, ["set due date of targetToDo to missing value"])
    Some(date) ->
      list.append(commands, [
        "set due date of targetToDo to date \"" <> date <> "\"",
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

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) { "Updated todo: " <> args.id })
}

// ===== SEARCH TODOS =====

pub fn handle_search_todos(
  args: types.SearchTodosArgs,
) -> Result(String, String) {
  // Build AppleScript to search across active built-in lists.
  let command = "
    set allTodos to {}
    set searchQuery to \"" <> args.query <> "\"

    repeat with listName in {\"Inbox\", \"Today\", \"Anytime\", \"Upcoming\", \"Someday\"}
      try
        set theList to list listName
        repeat with todo in to dos of theList
          try
            set todoName to name of todo
            if todoName contains searchQuery then
              set todoID to id of todo
              set todoStatus to status of todo as string
              set todoInfo to todoID & \" | \" & todoName & \" (\" & todoStatus & \")\"
              set end of allTodos to todoInfo
            end if
          end try
        end repeat
      end try
    end repeat

    if (count of allTodos) is 0 then
      return \"\"
    else
      set AppleScript's text item delimiters to linefeed
      set searchOutput to allTodos as text
      set AppleScript's text item delimiters to \"\"
      return searchOutput
    end if
  "

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    "Search results for \"" <> args.query <> "\":\n" <> output
  })
}
