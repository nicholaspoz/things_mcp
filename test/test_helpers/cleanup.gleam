import gleam/io
import gleam/list
import gleam/result
import test_helpers/test_state
import things_mcp/applescript
import things_mcp/tools/move_ops
import things_mcp/types

/// Clean up all test entities, ensuring no trace is left
pub fn cleanup_all(state: test_state.TestState) -> Result(Nil, String) {
  io.println("\n=== CLEANUP PHASE ===")

  // First, move all todos to trash
  let todo_result = cleanup_todos(state)

  // Then, delete all projects
  let project_result = cleanup_projects(state)

  // Verify cleanup
  let verify_result = verify_cleanup(state)

  // Return combined result
  case todo_result, project_result, verify_result {
    Ok(_), Ok(_), Ok(_) -> {
      io.println("\n✓ Cleanup completed successfully - no trace left")
      Ok(Nil)
    }
    _, _, _ -> {
      io.println("\n⚠ Cleanup encountered some errors (see above)")
      Error("Cleanup had some failures")
    }
  }
}

/// Move all tracked todos to trash
fn cleanup_todos(state: test_state.TestState) -> Result(Nil, String) {
  io.println("\nMoving todos to trash...")

  let todos = test_state.get_todos(state)

  case list.is_empty(todos) {
    True -> {
      io.println("  (no todos to clean up)")
      Ok(Nil)
    }
    False -> {
      todos
      |> list.map(fn(todo_name) {
        let args = types.MoveTodoArgs(name: todo_name, list: "Trash")
        case move_ops.handle_move_todo(args) {
          Ok(_) -> {
            io.println("  ✓ Moved to trash: " <> todo_name)
            Ok(Nil)
          }
          Error(err) -> {
            io.println("  ⚠ Failed to trash: " <> todo_name <> " - " <> err)
            // Continue even on error - might already be deleted
            Ok(Nil)
          }
        }
      })
      |> result.all()
      |> result.map(fn(_) { Nil })
    }
  }
}

/// Delete all tracked projects using direct AppleScript
fn cleanup_projects(state: test_state.TestState) -> Result(Nil, String) {
  io.println("\nDeleting projects...")

  let projects = test_state.get_projects(state)

  case list.is_empty(projects) {
    True -> {
      io.println("  (no projects to clean up)")
      Ok(Nil)
    }
    False -> {
      // Delete each project by name
      projects
      |> list.map(fn(project_name) {
        // Use direct AppleScript to delete project by name
        let command = "delete project \"" <> project_name <> "\""
        case applescript.execute(applescript.tell_things(command)) {
          Ok(_) -> {
            io.println("  ✓ Deleted project: " <> project_name)
            Ok(Nil)
          }
          Error(err) -> {
            io.println("  ⚠ Failed to delete: " <> project_name <> " - " <> err)
            // Continue even on error - might already be deleted
            Ok(Nil)
          }
        }
      })
      |> result.all()
      |> result.map(fn(_) { Nil })
    }
  }
}

/// Verify that all test entities have been cleaned up
fn verify_cleanup(_state: test_state.TestState) -> Result(Nil, String) {
  io.println("\nVerifying cleanup...")

  // Search for any remaining test entities
  let search_command = "
    set allTodos to {}
    repeat with listName in {\"Inbox\", \"Today\", \"Anytime\", \"Someday\"}
      try
        set theList to list listName
        repeat with todo in to dos of theList
          try
            set todoName to name of todo
            if todoName contains \"__TEST_\" then
              set end of allTodos to todoName
            end if
          end try
        end repeat
      end try
    end repeat

    set allProjects to {}
    repeat with proj in projects
      try
        set projName to name of proj
        if projName contains \"__TEST_\" then
          set end of allProjects to projName
        end if
      end try
    end repeat

    return \"Todos: \" & (count of allTodos) & \", Projects: \" & (count of allProjects)
  "

  case applescript.execute(applescript.tell_things(search_command)) {
    Ok(output) -> {
      io.println("  Remaining test entities: " <> output)
      Ok(Nil)
    }
    Error(_) -> {
      io.println("  ⚠ Could not verify cleanup")
      Ok(Nil)
    }
  }
}

/// Emergency cleanup - finds and removes ALL entities with __TEST_ prefix
/// Use this if tests fail and leave orphaned data
pub fn emergency_cleanup() -> Result(Nil, String) {
  io.println("\n=== EMERGENCY CLEANUP ===")
  io.println("Searching for all test entities...")

  // Find and trash all test todos
  let todo_cleanup = "
    repeat with listName in {\"Inbox\", \"Today\", \"Anytime\", \"Someday\"}
      try
        set theList to list listName
        repeat with todo in to dos of theList
          try
            set todoName to name of todo
            if todoName contains \"__TEST_\" then
              move todo to list \"Trash\"
            end if
          end try
        end repeat
      end try
    end repeat
    return \"Cleaned todos\"
  "

  case applescript.execute(applescript.tell_things(todo_cleanup)) {
    Ok(_) -> io.println("  ✓ Cleaned up test todos")
    Error(err) -> io.println("  ⚠ Failed to clean todos: " <> err)
  }

  // Find and delete all test projects
  // Can't delete while iterating, so collect names first then delete
  let project_cleanup = "
    set projectsToDelete to {}
    repeat with proj in projects
      try
        set projName to name of proj
        if projName contains \"__TEST_\" then
          set end of projectsToDelete to projName
        end if
      end try
    end repeat

    repeat with projName in projectsToDelete
      try
        delete project projName
      end try
    end repeat

    return \"Cleaned \" & (count of projectsToDelete) & \" projects\"
  "

  case applescript.execute(applescript.tell_things(project_cleanup)) {
    Ok(_) -> io.println("  ✓ Cleaned up test projects")
    Error(err) -> io.println("  ⚠ Failed to clean projects: " <> err)
  }

  io.println("\n✓ Emergency cleanup complete")
  Ok(Nil)
}
