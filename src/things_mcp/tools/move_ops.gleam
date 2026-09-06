import gleam/result
import things_mcp/applescript
import things_mcp/types
import things_mcp/validation
import things_mcp/write_checks as checks

// ===== MOVE TODO =====

pub fn handle_move_todo(args: types.MoveTodoArgs) -> Result(String, String) {
  use _ <- result.try(validation.validate_id(args.id))
  use _ <- result.try(case args.list {
    "Today" | "Anytime" | "Someday" | "Logbook" | "Trash" -> Ok(Nil)
    _ -> Error("Invalid target list")
  })
  let todo_ref = applescript.todo_by_id(args.id)

  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nmove targetToDo to list "
    <> applescript.quote_string(args.list)

  case args.list {
    "Trash" -> {
      use _ <- result.try(
        applescript.execute_write(applescript.tell_things(command)),
      )
      checks.verify_list(args.id, args.list)
    }
    _ ->
      checks.preserving_status(checks.Todo, args.id, command, fn() {
        checks.verify_list(args.id, args.list)
      })
  }
  |> result.map(fn(_output) { "Moved todo " <> args.id <> " to " <> args.list })
}

// ===== MOVE TODO TO PROJECT =====

pub fn handle_move_todo_to_project(
  args: types.MoveTodoToProjectArgs,
) -> Result(String, String) {
  use _ <- result.try(validation.validate_id(args.todo_id))
  let todo_ref = applescript.todo_by_id(args.todo_id)
  let project_ref = applescript.project_by_id(args.project_id)

  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nset targetProject to "
    <> project_ref
    <> "\nset project of targetToDo to targetProject"

  checks.preserving_status(checks.Todo, args.todo_id, command, fn() {
    checks.verify_project(args.todo_id, args.project_id)
  })
  |> result.map(fn(_output) {
    "Moved todo " <> args.todo_id <> " to project " <> args.project_id
  })
}

// ===== MOVE TODO TO AREA =====

pub fn handle_move_todo_to_area(
  args: types.MoveTodoToAreaArgs,
) -> Result(String, String) {
  use _ <- result.try(validation.validate_id(args.todo_id))
  let todo_ref = applescript.todo_by_id(args.todo_id)
  let area_ref = applescript.area_by_id(args.area_id)

  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nset targetArea to "
    <> area_ref
    <> "\nset area of targetToDo to targetArea"

  checks.preserving_status(checks.Todo, args.todo_id, command, fn() {
    checks.verify_area(checks.Todo, args.todo_id, args.area_id)
  })
  |> result.map(fn(_output) {
    "Moved todo " <> args.todo_id <> " to area " <> args.area_id
  })
}

// ===== MOVE PROJECT TO AREA =====

pub fn handle_move_project_to_area(
  args: types.MoveProjectToAreaArgs,
) -> Result(String, String) {
  use _ <- result.try(validation.validate_id(args.project_id))
  let project_ref = applescript.project_by_id(args.project_id)
  let area_ref = applescript.area_by_id(args.area_id)

  let command =
    "set targetProject to "
    <> project_ref
    <> "\nset targetArea to "
    <> area_ref
    <> "\nset area of targetProject to targetArea"

  checks.preserving_status(checks.Project, args.project_id, command, fn() {
    checks.verify_area(checks.Project, args.project_id, args.area_id)
  })
  |> result.map(fn(_output) {
    "Moved project " <> args.project_id <> " to area " <> args.area_id
  })
}

// ===== REMOVE TODO FROM PROJECT =====

pub fn handle_remove_todo_from_project(
  args: types.RemoveTodoFromProjectArgs,
) -> Result(String, String) {
  use _ <- result.try(validation.validate_id(args.id))
  let todo_ref = applescript.todo_by_id(args.id)
  let command =
    "set targetToDo to " <> todo_ref <> "\ndelete project of targetToDo"

  checks.preserving_status(checks.Todo, args.id, command, fn() {
    checks.verify_detached(checks.Todo, args.id)
  })
  |> result.map(fn(_output) {
    "Removed todo " <> args.id <> " from its project"
  })
}

// ===== REMOVE PROJECT FROM AREA =====

pub fn handle_remove_project_from_area(
  args: types.RemoveProjectFromAreaArgs,
) -> Result(String, String) {
  use _ <- result.try(validation.validate_id(args.id))
  let project_ref = applescript.project_by_id(args.id)
  let command =
    "set targetProject to " <> project_ref <> "\ndelete area of targetProject"

  checks.preserving_status(checks.Project, args.id, command, fn() {
    checks.verify_detached(checks.Project, args.id)
  })
  |> result.map(fn(_output) {
    "Removed project " <> args.id <> " from its area"
  })
}
