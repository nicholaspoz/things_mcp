import gleam/list
import gleam/option
import gleam/result
import gleam/string
import things_mcp/applescript
import things_mcp/types
import things_mcp/writes

// ===== CREATE TODO =====

pub fn handle_create_todo(
  args: types.CreateTodoArgs,
) -> Result(String, String) {
  writes.handle_create_todo(args)
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
  writes.handle_complete_todo(args)
}

// ===== UPDATE TODO =====

pub fn handle_update_todo(
  args: types.UpdateTodoArgs,
) -> Result(String, String) {
  writes.handle_update_todo(args)
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
