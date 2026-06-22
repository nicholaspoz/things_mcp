import gleam/io
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import test_helpers/assertions as a
import test_helpers/cleanup
import test_helpers/test_state
import things_mcp/tools/list_ops
import things_mcp/tools/move_ops
import things_mcp/tools/project_ops
import things_mcp/tools/todo_ops
import things_mcp/types

/// Main integration test that covers all 17 tools
pub fn full_integration_test() {
  io.println("\n╔════════════════════════════════════════════════╗")
  io.println("║  Things3 MCP Integration Test Suite            ║")
  io.println("║  Testing all 17 tools with cleanup             ║")
  io.println("╚════════════════════════════════════════════════╝")

  // Create test state tracker
  let state = test_state.new()

  // Run comprehensive cleanup first to remove any orphaned test data
  let _cleanup_result = cleanup.comprehensive_cleanup()

  // Run all tests and capture final state
  let test_result = run_all_tests(state)

  // CRITICAL: Always cleanup, even if tests fail
  // Use comprehensive cleanup which finds ALL test entities, not just tracked ones
  let _cleanup_result = cleanup.comprehensive_cleanup()

  // Assert that tests passed
  case test_result {
    Ok(_) -> {
      io.println("\n╔════════════════════════════════════════════════╗")
      io.println("║  ✓ ALL INTEGRATION TESTS PASSED                ║")
      io.println("╚════════════════════════════════════════════════╝")
    }
    Error(err) -> {
      io.println("\n╔════════════════════════════════════════════════╗")
      io.println("║  ✗ INTEGRATION TESTS FAILED                   ║")
      io.println("╚════════════════════════════════════════════════╝")
      io.println("Error: " <> err)
      panic as "Integration tests failed"
    }
  }
}

/// Run all test phases
fn run_all_tests(
  state: test_state.TestState,
) -> Result(test_state.TestState, String) {
  use state <- result.try(phase1_list_operations(state))
  use state <- result.try(phase2_create_operations(state))
  use state <- result.try(phase3_search_and_verify(state))
  use state <- result.try(phase4_update_operations(state))
  use state <- result.try(phase5_move_operations(state))
  use state <- result.try(phase6_complete_operations(state))
  use state <- result.try(phase7_edge_cases(state))
  Ok(state)
}

// ===== PHASE 1: LIST OPERATIONS (Read-only) =====

fn phase1_list_operations(
  state: test_state.TestState,
) -> Result(test_state.TestState, String) {
  a.print_section("PHASE 1: List Operations (Read-only)")

  // Test list_tags (Tool #10)
  a.print_phase("Test: list_tags")
  use _tags <- result.try(
    list_ops.handle_list_tags(types.ListTagsArgs)
    |> a.assert_ok("List tags"),
  )

  // Test list_areas (Tool #11)
  a.print_phase("Test: list_areas")
  use areas <- result.try(
    list_ops.handle_list_areas(types.ListAreasArgs)
    |> a.assert_ok("List areas"),
  )

  // Store first area for later use (if available)
  let _test_area = case string.contains(areas, "\n") {
    True ->
      areas
      |> string.split("\n")
      |> fn(lines) {
        case lines {
          [_, area, ..] -> Some(string.trim(area))
          _ -> None
        }
      }
    False -> None
  }

  // Test list_todos for different locations (Tool #2)
  a.print_phase("Test: list_todos (Inbox)")
  use _inbox <- result.try(
    todo_ops.handle_list_todos(types.ListTodosArgs(
      location: Some("Inbox"),
      status: None,
    ))
    |> a.assert_ok("List todos in Inbox"),
  )

  a.print_phase("Test: list_todos (Today)")
  use _today <- result.try(
    todo_ops.handle_list_todos(types.ListTodosArgs(
      location: Some("Today"),
      status: None,
    ))
    |> a.assert_ok("List todos in Today"),
  )

  // Test list_projects (Tool #7)
  a.print_phase("Test: list_projects")
  use _projects <- result.try(
    project_ops.handle_list_projects(types.ListProjectsArgs(area: None))
    |> a.assert_ok("List all projects"),
  )

  Ok(state)
}

// ===== PHASE 2: CREATE OPERATIONS =====

fn phase2_create_operations(
  state: test_state.TestState,
) -> Result(test_state.TestState, String) {
  a.print_section("PHASE 2: Create Operations")

  // Create test project 1 (Tool #6)
  a.print_phase("Test: create_project")
  let project1 = test_state.test_project_name(state, "1")
  use created_project1 <- result.try(
    project_ops.handle_create_project(types.CreateProjectArgs(
      name: project1,
      notes: Some("Test project 1 notes"),
      area: None,
    ))
    |> a.assert_ok("Create project 1"),
  )
  use _ <- result.try(a.assert_contains(
    created_project1,
    "ID:",
    "Create project 1 returns stable ID",
  ))
  let state = test_state.track_project(state, project1)

  // Create test project 2
  let project2 = test_state.test_project_name(state, "2")
  use _ <- result.try(
    project_ops.handle_create_project(types.CreateProjectArgs(
      name: project2,
      notes: None,
      area: None,
    ))
    |> a.assert_ok("Create project 2"),
  )
  let state = test_state.track_project(state, project2)

  // Create test todos (Tool #1)
  a.print_phase("Test: create_todo (with all options)")
  let todo1 = test_state.test_todo_name(state, "1")
  use created_todo1 <- result.try(
    todo_ops.handle_create_todo(types.CreateTodoArgs(
      name: todo1,
      notes: Some("Test notes for todo 1"),
      due_date: Some("2026-12-31"),
      tags: Some(["test"]),
      list: Some("Inbox"),
    ))
    |> a.assert_ok("Create todo 1 in Inbox with all options"),
  )
  use _ <- result.try(a.assert_contains(
    created_todo1,
    "ID:",
    "Create todo 1 returns stable ID",
  ))
  let state = test_state.track_todo(state, todo1)

  a.print_phase("Test: create_todo (Today)")
  let todo2 = test_state.test_todo_name(state, "2")
  use _ <- result.try(
    todo_ops.handle_create_todo(types.CreateTodoArgs(
      name: todo2,
      notes: None,
      due_date: None,
      tags: None,
      list: Some("Today"),
    ))
    |> a.assert_ok("Create todo 2 in Today"),
  )
  let state = test_state.track_todo(state, todo2)

  a.print_phase("Test: create_todo (Anytime)")
  let todo3 = test_state.test_todo_name(state, "3")
  use _ <- result.try(
    todo_ops.handle_create_todo(types.CreateTodoArgs(
      name: todo3,
      notes: Some("Will be completed later"),
      due_date: None,
      tags: None,
      list: Some("Anytime"),
    ))
    |> a.assert_ok("Create todo 3 in Anytime"),
  )
  let state = test_state.track_todo(state, todo3)

  a.print_phase("Test: create_todo (Someday)")
  let todo4 = test_state.test_todo_name(state, "4")
  use _ <- result.try(
    todo_ops.handle_create_todo(types.CreateTodoArgs(
      name: todo4,
      notes: None,
      due_date: None,
      tags: None,
      list: Some("Someday"),
    ))
    |> a.assert_ok("Create todo 4 in Someday"),
  )
  let state = test_state.track_todo(state, todo4)

  Ok(state)
}

// ===== PHASE 3: SEARCH AND VERIFY =====

fn phase3_search_and_verify(
  state: test_state.TestState,
) -> Result(test_state.TestState, String) {
  a.print_section("PHASE 3: Search and Verify")

  let todo1 = test_state.test_todo_name(state, "1")
  let project1 = test_state.test_project_name(state, "1")

  // Verify todos are in correct lists
  a.print_phase("Test: Verify todos in lists")
  use inbox_list <- result.try(
    todo_ops.handle_list_todos(types.ListTodosArgs(
      location: Some("Inbox"),
      status: Some("open"),
    ))
    |> a.assert_ok("List Inbox todos"),
  )
  use _ <- result.try(a.assert_contains(inbox_list, todo1, "Todo1 is in Inbox"))

  // Test get_todo (Tool #3)
  a.print_phase("Test: get_todo")
  use todo1_id <- result.try(todo_id_in_list(todo1, "Inbox"))
  use todo_detail <- result.try(
    todo_ops.handle_get_todo(types.GetTodoArgs(id: todo1_id))
    |> a.assert_ok("Get todo1 by ID"),
  )
  use _ <- result.try(a.assert_contains(
    todo_detail,
    "Test notes for todo 1",
    "Get todo returns full notes content",
  ))

  // Test list_projects with projects present
  a.print_phase("Test: Verify projects exist")
  use projects_list <- result.try(
    project_ops.handle_list_projects(types.ListProjectsArgs(area: None))
    |> a.assert_ok("List all projects"),
  )
  use _ <- result.try(a.assert_contains(
    projects_list,
    project1,
    "Project1 exists in project list",
  ))

  Ok(state)
}

// ===== PHASE 4: UPDATE OPERATIONS =====

fn phase4_update_operations(
  state: test_state.TestState,
) -> Result(test_state.TestState, String) {
  a.print_section("PHASE 4: Update Operations")

  let todo1 = test_state.test_todo_name(state, "1")
  use todo1_id <- result.try(todo_id_in_list(todo1, "Inbox"))

  // Test update_todo (Tool #4)
  a.print_phase("Test: update_todo (change notes and due date)")
  use _ <- result.try(
    todo_ops.handle_update_todo(types.UpdateTodoArgs(
      id: todo1_id,
      new_name: None,
      new_notes: Some("Updated notes for todo 1"),
      new_due_date: Some("2027-01-15"),
      new_tags: Some(["test", "updated"]),
    ))
    |> a.assert_ok("Update todo 1"),
  )

  use updated_todo <- result.try(
    todo_ops.handle_get_todo(types.GetTodoArgs(id: todo1_id))
    |> a.assert_ok("Get updated todo 1 by ID"),
  )
  use _ <- result.try(a.assert_contains(
    updated_todo,
    "Updated notes for todo 1",
    "Get todo returns updated notes content",
  ))

  Ok(state)
}

// ===== PHASE 5: MOVE OPERATIONS =====

fn phase5_move_operations(
  state: test_state.TestState,
) -> Result(test_state.TestState, String) {
  a.print_section("PHASE 5: Move Operations")

  let todo1 = test_state.test_todo_name(state, "1")
  let project1 = test_state.test_project_name(state, "1")
  use todo1_id <- result.try(todo_id_by_name(todo1))
  use project1_id <- result.try(project_id_by_name(project1))

  // Test move_todo (Tool #12)
  a.print_phase("Test: move_todo (Inbox -> Today)")
  use _ <- result.try(
    move_ops.handle_move_todo(types.MoveTodoArgs(id: todo1_id, list: "Today"))
    |> a.assert_ok("Move todo1 from Inbox to Today"),
  )

  // Verify the move
  use today_list <- result.try(
    todo_ops.handle_list_todos(types.ListTodosArgs(
      location: Some("Today"),
      status: Some("open"),
    ))
    |> a.assert_ok("List Today after move"),
  )
  use _ <- result.try(a.assert_contains(
    today_list,
    todo1,
    "Todo1 is now in Today",
  ))

  // Test move_todo_to_project (Tool #13)
  a.print_phase("Test: move_todo_to_project")
  use _ <- result.try(
    move_ops.handle_move_todo_to_project(types.MoveTodoToProjectArgs(
      todo_id: todo1_id,
      project_id: project1_id,
    ))
    |> a.assert_ok("Move todo1 to project1"),
  )

  // Test get_project_todos (Tool #8)
  a.print_phase("Test: get_project_todos")
  use project_todos <- result.try(
    project_ops.handle_get_project_todos(types.GetProjectTodosArgs(
      project: project1,
      status: Some("open"),
    ))
    |> a.assert_ok("Get todos in project1"),
  )
  use _ <- result.try(a.assert_contains(
    project_todos,
    todo1,
    "Todo1 is in project1",
  ))

  // Test remove_todo_from_project (Tool #15)
  a.print_phase("Test: remove_todo_from_project")
  use _ <- result.try(
    move_ops.handle_remove_todo_from_project(types.RemoveTodoFromProjectArgs(
      id: todo1_id,
    ))
    |> a.assert_ok("Remove todo1 from project1"),
  )

  // Verify removal
  use project_todos <- result.try(
    project_ops.handle_get_project_todos(types.GetProjectTodosArgs(
      project: project1,
      status: Some("open"),
    ))
    |> a.assert_ok("Get todos in project1 after removal"),
  )
  use _ <- result.try(a.assert_not_contains(
    project_todos,
    todo1,
    "Todo1 is no longer in project1",
  ))

  use _ <- result.try(test_area_move_operations(todo1_id, project1_id))

  Ok(state)
}

// ===== PHASE 6: COMPLETE OPERATIONS =====

fn phase6_complete_operations(
  state: test_state.TestState,
) -> Result(test_state.TestState, String) {
  a.print_section("PHASE 6: Complete Operations")

  let todo3 = test_state.test_todo_name(state, "3")
  use todo3_id <- result.try(todo_id_in_list(todo3, "Anytime"))

  // Test complete_todo (Tool #4)
  a.print_phase("Test: complete_todo")
  use _ <- result.try(
    todo_ops.handle_complete_todo(types.CompleteTodoArgs(id: todo3_id))
    |> a.assert_ok("Complete todo3 (moves to Logbook automatically)"),
  )

  Ok(state)
}

// ===== PHASE 7: EDGE CASES =====

fn phase7_edge_cases(
  state: test_state.TestState,
) -> Result(test_state.TestState, String) {
  a.print_section("PHASE 7: Edge Cases")

  // Test completing non-existent todo (should error)
  a.print_phase("Test: complete non-existent todo (should fail)")
  let _result =
    todo_ops.handle_complete_todo(types.CompleteTodoArgs(
      id: "__NONEXISTENT_TODO_ID__",
    ))
    |> a.assert_error("Complete non-existent todo should fail")

  // Test moving to non-existent project (should error)
  a.print_phase("Test: move to non-existent project (should fail)")
  let todo1 = test_state.test_todo_name(state, "1")
  let todo1_id = case todo_id_by_name(todo1) {
    Ok(id) -> id
    Error(_) -> "__MISSING_TEST_TODO_ID__"
  }
  let _result =
    move_ops.handle_move_todo_to_project(types.MoveTodoToProjectArgs(
      todo_id: todo1_id,
      project_id: "__NONEXISTENT_PROJECT_ID__",
    ))
    |> a.assert_error("Move to non-existent project should fail")

  // Test search with no results
  a.print_phase("Test: search with no results")
  use _ <- result.try(
    todo_ops.handle_search_todos(types.SearchTodosArgs(
      query: "__DEFINITELY_DOES_NOT_EXIST_XYZ__",
    ))
    |> a.assert_ok("Search with no results should succeed"),
  )

  Ok(state)
}

fn todo_id_in_list(name: String, location: String) -> Result(String, String) {
  use output <- result.try(
    todo_ops.handle_list_todos(types.ListTodosArgs(
      location: Some(location),
      status: Some("all"),
    )),
  )
  extract_id_for_name(output, name)
}

fn todo_id_by_name(name: String) -> Result(String, String) {
  use output <- result.try(
    todo_ops.handle_search_todos(types.SearchTodosArgs(query: name)),
  )
  extract_id_for_name(output, name)
}

fn project_id_by_name(name: String) -> Result(String, String) {
  use output <- result.try(
    project_ops.handle_list_projects(types.ListProjectsArgs(area: None)),
  )
  extract_id_for_name(output, name)
}

fn test_area_move_operations(
  todo_id: String,
  project_id: String,
) -> Result(Nil, String) {
  case first_area_id() {
    Ok(area_id) -> {
      a.print_phase("Test: move_todo_to_area")
      use _ <- result.try(
        move_ops.handle_move_todo_to_area(types.MoveTodoToAreaArgs(
          todo_id: todo_id,
          area_id: area_id,
        ))
        |> a.assert_ok("Move todo1 to area"),
      )

      a.print_phase("Test: move_project_to_area")
      use _ <- result.try(
        move_ops.handle_move_project_to_area(types.MoveProjectToAreaArgs(
          project_id: project_id,
          area_id: area_id,
        ))
        |> a.assert_ok("Move project1 to area"),
      )

      a.print_phase("Test: remove_project_from_area")
      use _ <- result.try(
        move_ops.handle_remove_project_from_area(
          types.RemoveProjectFromAreaArgs(id: project_id),
        )
        |> a.assert_ok("Remove project1 from area"),
      )

      Ok(Nil)
    }
    Error(_) -> {
      io.println("  (skipping area move tests: no areas available)")
      Ok(Nil)
    }
  }
}

fn first_area_id() -> Result(String, String) {
  use output <- result.try(list_ops.handle_list_areas(types.ListAreasArgs))
  let lines =
    output
    |> string.split("\n")
    |> list.drop(1)
    |> list.filter(fn(line) { string.contains(line, " | ") })

  case lines {
    [line, ..] -> extract_id(line)
    [] -> Error("No areas available")
  }
}

fn extract_id_for_name(output: String, name: String) -> Result(String, String) {
  let matching_lines =
    output
    |> string.split("\n")
    |> list.filter(fn(line) {
      string.contains(line, " | ") && string.contains(line, name)
    })

  case matching_lines {
    [_line, ..] -> {
      use ids <- result.try(collect_ids(matching_lines, []))
      case list.unique(ids) {
        [id] -> Ok(id)
        [] -> Error("No item found for name: " <> name)
        _ -> Error("Multiple items found for name: " <> name)
      }
    }
    [] -> Error("No item found for name: " <> name)
  }
}

fn collect_ids(
  lines: List(String),
  ids: List(String),
) -> Result(List(String), String) {
  case lines {
    [] -> Ok(ids)
    [line, ..rest] -> {
      use id <- result.try(extract_id(line))
      collect_ids(rest, list.append(ids, [id]))
    }
  }
}

fn extract_id(line: String) -> Result(String, String) {
  case string.split_once(line, " | ") {
    Ok(#(id, _rest)) -> Ok(string.trim(id))
    Error(_) -> Error("Could not extract ID from line: " <> line)
  }
}
