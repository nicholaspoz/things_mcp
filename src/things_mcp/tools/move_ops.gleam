import things_mcp/types
import things_mcp/writes

pub fn handle_move_todo(args: types.MoveTodoArgs) -> Result(String, String) {
  writes.handle_move_todo(args)
}

pub fn handle_move_todo_to_project(
  args: types.MoveTodoToProjectArgs,
) -> Result(String, String) {
  writes.handle_move_todo_to_project(args)
}

pub fn handle_move_todo_to_area(
  args: types.MoveTodoToAreaArgs,
) -> Result(String, String) {
  writes.handle_move_todo_to_area(args)
}

pub fn handle_move_project_to_area(
  args: types.MoveProjectToAreaArgs,
) -> Result(String, String) {
  writes.handle_move_project_to_area(args)
}

pub fn handle_remove_todo_from_project(
  args: types.RemoveTodoFromProjectArgs,
) -> Result(String, String) {
  writes.handle_remove_todo_from_project(args)
}

pub fn handle_remove_project_from_area(
  args: types.RemoveProjectFromAreaArgs,
) -> Result(String, String) {
  writes.handle_remove_project_from_area(args)
}
