import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import things_mcp/applescript
import things_mcp/types
import things_mcp/write_checks as checks

// ===== CREATE PROJECT =====

pub fn handle_create_project(
  args: types.CreateProjectArgs,
) -> Result(String, String) {
  use area <- result.try(case args.area {
    None -> Ok(None)
    Some(name) -> checks.area_id_by_name(name) |> result.map(Some)
  })
  // Build properties list
  let props = [#("name", applescript.quote_string(args.name))]

  // Add optional properties
  let props = case args.notes {
    Some(notes) ->
      list.append(props, [#("notes", applescript.quote_string(notes))])
    None -> props
  }

  let props = case area {
    Some(area) -> list.append(props, [#("area", applescript.area_by_id(area))])
    None -> props
  }

  let properties = applescript.build_properties(props)

  // Build and execute AppleScript command
  let command =
    "set newProject to make new project with properties "
    <> properties
    <> "\nreturn id of newProject"

  use output <- result.try(
    applescript.execute_write(applescript.tell_things(command)),
  )
  let id = string.trim(output)
  use _ <- result.try(checks.created(
    id,
    checks.verify_project_create(id, args, area),
  ))
  Ok("Created project: " <> args.name <> "\nID: " <> output)
}

// ===== LIST PROJECTS =====

pub fn handle_list_projects(
  args: types.ListProjectsArgs,
) -> Result(String, String) {
  // Build AppleScript to get projects with properties
  let command = case args.area {
    Some(area) -> "
    set projectList to {}
    try
      set theArea to area " <> applescript.quote_string(area) <> "
      repeat with proj in projects of theArea
        try
          set projID to id of proj
          set projName to name of proj
          set projStatus to status of proj as string
          set projNotes to notes of proj
          set projInfo to projID & \" | \" & projName & \" | \" & projStatus & \" | \" & projNotes
          set end of projectList to projInfo
        end try
      end repeat
    end try
    set AppleScript's text item delimiters to linefeed
    set projectOutput to projectList as text
    set AppleScript's text item delimiters to \"\"
    return projectOutput
  "
    None ->
      "
    set projectList to {}
    repeat with proj in projects
      try
        set projID to id of proj
        set projName to name of proj
        set projStatus to status of proj as string
        set projNotes to notes of proj
        set projAreaName to \"\"
        try
          set projAreaName to name of area of proj
        end try
        set projInfo to projID & \" | \" & projName & \" | \" & projStatus & \" | \" & projNotes & \" | Area: \" & projAreaName
        set end of projectList to projInfo
      end try
    end repeat
    set AppleScript's text item delimiters to linefeed
    set projectOutput to projectList as text
    set AppleScript's text item delimiters to \"\"
    return projectOutput
  "
  }

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    case args.area {
      Some(area) -> "Projects in area \"" <> area <> "\":\n" <> output
      None -> "All projects:\n" <> output
    }
  })
}

// ===== GET PROJECT TODOS =====

pub fn handle_get_project_todos(
  args: types.GetProjectTodosArgs,
) -> Result(String, String) {
  let status_filter = option.unwrap(args.status, "open")

  // Build AppleScript to get todos from a project
  let command = "
    set todoList to {}
    try
      set theProject to project " <> applescript.quote_string(args.project) <> "
      repeat with todo in to dos of theProject
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
    end try
    set AppleScript's text item delimiters to linefeed
    set todoOutput to todoList as text
    set AppleScript's text item delimiters to \"\"
    return todoOutput
  "

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) {
    let filtered = filter_by_status(output, status_filter)
    "Todos in project \"" <> args.project <> "\":\n" <> filtered
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
