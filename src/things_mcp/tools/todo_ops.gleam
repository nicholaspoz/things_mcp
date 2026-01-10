import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import things_mcp/applescript
import things_mcp/types

// ===== CREATE TODO =====

pub fn handle_create_todo(args: types.CreateTodoArgs) -> Result(String, String) {
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
    "make new to do in list \""
    <> target_list
    <> "\" with properties "
    <> properties

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    "Created todo: " <> args.name <> "\nOutput: " <> output
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
        set todoStatus to status of todo as string
        set todoNotes to notes of todo
        set todoDueDate to \"\"
        try
          set todoDueDate to due date of todo as string
        end try
        set todoTags to tag names of todo as string
        set todoInfo to todoName & \" | \" & todoStatus & \" | \" & todoNotes & \" | \" & todoDueDate & \" | \" & todoTags
        set end of todoList to todoInfo
      end try
    end repeat
    return todoList as string
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

// ===== COMPLETE TODO =====

pub fn handle_complete_todo(
  args: types.CompleteTodoArgs,
) -> Result(String, String) {
  let command = "set status of to do named \"" <> args.name <> "\" to completed"

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) { "Completed todo: " <> args.name })
}

// ===== UPDATE TODO =====

pub fn handle_update_todo(args: types.UpdateTodoArgs) -> Result(String, String) {
  // Build list of update commands
  let commands = []

  let commands = case args.new_name {
    Some(new_name) ->
      list.append(commands, [
        "set name of to do named \""
        <> args.name
        <> "\" to \""
        <> new_name
        <> "\"",
      ])
    None -> commands
  }

  let commands = case args.new_notes {
    Some(new_notes) ->
      list.append(commands, [
        "set notes of to do named \""
        <> args.name
        <> "\" to \""
        <> new_notes
        <> "\"",
      ])
    None -> commands
  }

  let commands = case args.new_due_date {
    Some("none") ->
      list.append(commands, [
        "set due date of to do named \"" <> args.name <> "\" to missing value",
      ])
    Some(date) ->
      list.append(commands, [
        "set due date of to do named \""
        <> args.name
        <> "\" to date \""
        <> date
        <> "\"",
      ])
    None -> commands
  }

  let commands = case args.new_tags {
    Some(tags) -> {
      let tag_string = string.join(tags, ", ")
      list.append(commands, [
        "set tag names of to do named \""
        <> args.name
        <> "\" to \""
        <> tag_string
        <> "\"",
      ])
    }
    None -> commands
  }

  // Execute all update commands
  let command = string.join(commands, "\n")

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) { "Updated todo: " <> args.name })
}

// ===== SEARCH TODOS =====

pub fn handle_search_todos(
  args: types.SearchTodosArgs,
) -> Result(String, String) {
  // Build AppleScript to search across all lists
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
              set todoStatus to status of todo as string
              set todoInfo to \"[\" & listName & \"] \" & todoName & \" (\" & todoStatus & \")\"
              set end of allTodos to todoInfo
            end if
          end try
        end repeat
      end try
    end repeat

    return allTodos as string
  "

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    "Search results for \"" <> args.query <> "\":\n" <> output
  })
}
