import gleam/int
import gleam/list
import gleam/string

@external(erlang, "erlang", "system_time")
fn system_time_ms() -> Int

/// Tracks created entities for cleanup
pub type TestState {
  TestState(
    todos: List(String),
    projects: List(String),
    timestamp: String,
  )
}

/// Create a new test state tracker with a unique timestamp
pub fn new() -> TestState {
  let timestamp = int.to_string(system_time_ms())
  TestState(todos: [], projects: [], timestamp: timestamp)
}

/// Generate a unique test todo name
pub fn test_todo_name(state: TestState, id: String) -> String {
  "__TEST_TODO_" <> state.timestamp <> "_" <> id <> "__"
}

/// Generate a unique test project name
pub fn test_project_name(state: TestState, id: String) -> String {
  "__TEST_PROJECT_" <> state.timestamp <> "_" <> id <> "__"
}

/// Track a todo for cleanup
pub fn track_todo(state: TestState, name: String) -> TestState {
  TestState(..state, todos: list.append(state.todos, [name]))
}

/// Track a project for cleanup
pub fn track_project(state: TestState, name: String) -> TestState {
  TestState(..state, projects: list.append(state.projects, [name]))
}

/// Get all tracked todos
pub fn get_todos(state: TestState) -> List(String) {
  state.todos
}

/// Get all tracked projects
pub fn get_projects(state: TestState) -> List(String) {
  state.projects
}

/// Check if a string contains the test prefix
pub fn is_test_entity(name: String) -> Bool {
  string.contains(name, "__TEST_")
}
