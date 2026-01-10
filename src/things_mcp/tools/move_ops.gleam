import gleam/result
import things_mcp/applescript
import things_mcp/types

// ===== MOVE TODO =====

pub fn handle_move_todo(args: types.MoveTodoArgs) -> Result(String, String) {
  // Use the move command to relocate todo to a built-in list
  let command =
    "move to do named \""
    <> args.name
    <> "\" to list \""
    <> args.list
    <> "\""

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Moved todo \"" <> args.name <> "\" to " <> args.list
  })
}

// ===== MOVE TODO TO PROJECT =====

pub fn handle_move_todo_to_project(
  args: types.MoveTodoToProjectArgs,
) -> Result(String, String) {
  // Set the project property to assign todo to a project
  let command =
    "set project of to do named \""
    <> args.name
    <> "\" to project \""
    <> args.project
    <> "\""

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Moved todo \"" <> args.name <> "\" to project \"" <> args.project <> "\""
  })
}

// ===== MOVE TODO TO AREA =====

pub fn handle_move_todo_to_area(
  args: types.MoveTodoToAreaArgs,
) -> Result(String, String) {
  // Set the area property to assign todo to an area
  // This will remove it from any project it's in
  let command =
    "set area of to do named \""
    <> args.name
    <> "\" to area \""
    <> args.area
    <> "\""

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Moved todo \"" <> args.name <> "\" to area \"" <> args.area <> "\""
  })
}

// ===== MOVE PROJECT TO AREA =====

pub fn handle_move_project_to_area(
  args: types.MoveProjectToAreaArgs,
) -> Result(String, String) {
  // Set the area property to assign project to an area
  let command =
    "set area of project \""
    <> args.name
    <> "\" to area \""
    <> args.area
    <> "\""

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Moved project \"" <> args.name <> "\" to area \"" <> args.area <> "\""
  })
}

// ===== REMOVE TODO FROM PROJECT =====

pub fn handle_remove_todo_from_project(
  args: types.RemoveTodoFromProjectArgs,
) -> Result(String, String) {
  // Delete the project property to detach todo from its project
  let command = "delete project of to do named \"" <> args.name <> "\""

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Removed todo \"" <> args.name <> "\" from its project"
  })
}

// ===== REMOVE PROJECT FROM AREA =====

pub fn handle_remove_project_from_area(
  args: types.RemoveProjectFromAreaArgs,
) -> Result(String, String) {
  // Delete the area property to detach project from its area
  let command = "delete area of project \"" <> args.name <> "\""

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(_output) {
    "Removed project \"" <> args.name <> "\" from its area"
  })
}
