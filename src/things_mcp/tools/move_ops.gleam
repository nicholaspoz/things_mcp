import gleam/result
import things_mcp/applescript
import things_mcp/types

// ===== MOVE TODO =====

pub fn handle_move_todo(args: types.MoveTodoArgs) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.id)

  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nmove targetToDo to list "
    <> applescript.quote_string(args.list)

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) { "Moved todo " <> args.id <> " to " <> args.list })
}

// ===== MOVE TODO TO PROJECT =====

pub fn handle_move_todo_to_project(
  args: types.MoveTodoToProjectArgs,
) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.todo_id)
  let project_ref = applescript.project_by_id(args.project_id)

  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nset targetProject to "
    <> project_ref
    <> "\nset project of targetToDo to targetProject"

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Moved todo " <> args.todo_id <> " to project " <> args.project_id
  })
}

// ===== MOVE TODO TO AREA =====

pub fn handle_move_todo_to_area(
  args: types.MoveTodoToAreaArgs,
) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.todo_id)
  let area_ref = applescript.area_by_id(args.area_id)

  let command =
    "set targetToDo to "
    <> todo_ref
    <> "\nset targetArea to "
    <> area_ref
    <> "\nset area of targetToDo to targetArea"

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Moved todo " <> args.todo_id <> " to area " <> args.area_id
  })
}

// ===== MOVE PROJECT TO AREA =====

pub fn handle_move_project_to_area(
  args: types.MoveProjectToAreaArgs,
) -> Result(String, String) {
  let project_ref = applescript.project_by_id(args.project_id)
  let area_ref = applescript.area_by_id(args.area_id)

  let command =
    "set targetProject to "
    <> project_ref
    <> "\nset targetArea to "
    <> area_ref
    <> "\nset area of targetProject to targetArea"

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Moved project " <> args.project_id <> " to area " <> args.area_id
  })
}

// ===== REMOVE TODO FROM PROJECT =====

pub fn handle_remove_todo_from_project(
  args: types.RemoveTodoFromProjectArgs,
) -> Result(String, String) {
  let todo_ref = applescript.todo_by_id(args.id)
  let command =
    "set targetToDo to " <> todo_ref <> "\ndelete project of targetToDo"

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Removed todo " <> args.id <> " from its project"
  })
}

// ===== REMOVE PROJECT FROM AREA =====

pub fn handle_remove_project_from_area(
  args: types.RemoveProjectFromAreaArgs,
) -> Result(String, String) {
  let project_ref = applescript.project_by_id(args.id)
  let command =
    "set targetProject to " <> project_ref <> "\ndelete area of targetProject"

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Removed project " <> args.id <> " from its area"
  })
}
