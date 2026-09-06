//// Coordinates the existing tool contract over JSON and known compatibility fallbacks.

import gleam/option.{type Option, None, Some}
import gleam/result
import gleam/string
import things_mcp/json_payload
import things_mcp/json_transport
import things_mcp/legacy_writes
import things_mcp/types
import things_mcp/write_checks as checks

fn oversized(notes: Option(String)) -> Bool {
  case notes {
    Some(value) -> string.byte_size(value) > 10_000
    None -> False
  }
}

pub fn handle_create_todo(
  args: types.CreateTodoArgs,
) -> Result(String, String) {
  use payload <- result.try(json_payload.create_todo(args))
  use fallback <- result.try(checks.tags_need_fallback(args.tags))
  case fallback || oversized(args.notes) || string.byte_size(args.name) > 4000 {
    True -> legacy_writes.handle_create_todo(args)
    False -> {
      use id <- result.try(create(payload))
      use _ <- result.try(verified(checks.verify_todo_create(id, args)))
      Ok("Created todo: " <> args.name <> "\nID: " <> id)
    }
  }
}

pub fn handle_create_project(
  args: types.CreateProjectArgs,
) -> Result(String, String) {
  use area <- result.try(case args.area {
    None -> Ok(None)
    Some(name) -> checks.area_id_by_name(name) |> result.map(Some)
  })
  use payload <- result.try(json_payload.create_project(args, area))
  case oversized(args.notes) || string.byte_size(args.name) > 4000 {
    True -> legacy_writes.handle_create_project(args)
    False -> {
      use id <- result.try(create(payload))
      use _ <- result.try(
        verified(checks.verify_project_create(id, args, area)),
      )
      Ok("Created project: " <> args.name <> "\nID: " <> id)
    }
  }
}

pub fn handle_update_todo(
  args: types.UpdateTodoArgs,
) -> Result(String, String) {
  use payload <- result.try(json_payload.update_todo(args))
  use status <- result.try(checks.status(checks.Todo, args.id))
  use fallback <- result.try(checks.tags_need_fallback(args.new_tags))
  // Recurrence is not exposed by supported reads. Preselect the legacy backend
  // for deadline updates rather than retrying a JSON write on a repeating item.
  case
    fallback
    || oversized(args.new_notes)
    || args.new_due_date != None
    || oversized_title(args.new_name)
  {
    True -> {
      use output <- result.try(legacy_writes.handle_update_todo(args))
      use _ <- result.try(verified(checks.verify_todo_update(args.id, args)))
      use _ <- result.try(
        verified(checks.verify_status(checks.Todo, args.id, status)),
      )
      Ok(output)
    }
    False -> {
      use _ <- result.try(json_transport.execute(payload, True))
      use _ <- result.try(verified(checks.verify_todo_update(args.id, args)))
      use _ <- result.try(
        verified(checks.verify_status(checks.Todo, args.id, status)),
      )
      Ok("Updated todo: " <> args.id)
    }
  }
}

pub fn handle_complete_todo(
  args: types.CompleteTodoArgs,
) -> Result(String, String) {
  use _ <- result.try(json_payload.validate_id(args.id))
  use output <- result.try(legacy_writes.handle_complete_todo(args))
  use _ <- result.try(verified(checks.verify_completed(args.id)))
  Ok(output)
}

fn create(payload: String) -> Result(String, String) {
  use id <- result.try(json_transport.execute(payload, False))
  case id {
    Some(value) -> Ok(value)
    None -> Error("Things create returned no ID; completion is uncertain")
  }
}

fn verified(outcome: Result(Nil, String)) -> Result(Nil, String) {
  result.map_error(outcome, fn(error) {
    "Things reported success but verification failed; completion is uncertain; do not retry automatically: "
    <> error
  })
}

fn oversized_title(title: Option(String)) -> Bool {
  case title {
    Some(value) -> string.byte_size(value) > 4000
    None -> False
  }
}

pub fn handle_move_todo(args: types.MoveTodoArgs) -> Result(String, String) {
  use _ <- result.try(json_payload.validate_id(args.id))
  // Scheduling updates on repeating items are restricted by Things JSON.
  case args.list {
    "Today" | "Anytime" | "Someday" | "Logbook" | "Trash" -> {
      use output <- result.try(legacy_writes.handle_move_todo(args))
      use _ <- result.try(verified(checks.verify_list(args.id, args.list)))
      Ok(output)
    }
    _ -> Error("Invalid target list")
  }
}

pub fn handle_move_todo_to_project(
  args: types.MoveTodoToProjectArgs,
) -> Result(String, String) {
  use payload <- result.try(json_payload.move_todo_to_project(
    args.todo_id,
    args.project_id,
  ))
  use status <- result.try(checks.status(checks.Todo, args.todo_id))
  use _ <- result.try(checks.exists(checks.Project, args.project_id))
  use _ <- result.try(json_transport.execute(payload, True))
  use _ <- result.try(
    verified(checks.verify_project(args.todo_id, args.project_id)),
  )
  use _ <- result.try(
    verified(checks.verify_status(checks.Todo, args.todo_id, status)),
  )
  Ok("Moved todo " <> args.todo_id <> " to project " <> args.project_id)
}

pub fn handle_move_todo_to_area(
  args: types.MoveTodoToAreaArgs,
) -> Result(String, String) {
  use payload <- result.try(json_payload.move_todo_to_area(
    args.todo_id,
    args.area_id,
  ))
  use status <- result.try(checks.status(checks.Todo, args.todo_id))
  use _ <- result.try(checks.area_exists(args.area_id))
  use _ <- result.try(json_transport.execute(payload, True))
  use _ <- result.try(
    verified(checks.verify_area(checks.Todo, args.todo_id, args.area_id)),
  )
  use _ <- result.try(
    verified(checks.verify_status(checks.Todo, args.todo_id, status)),
  )
  Ok("Moved todo " <> args.todo_id <> " to area " <> args.area_id)
}

pub fn handle_move_project_to_area(
  args: types.MoveProjectToAreaArgs,
) -> Result(String, String) {
  use payload <- result.try(json_payload.move_project_to_area(
    args.project_id,
    args.area_id,
  ))
  use status <- result.try(checks.status(checks.Project, args.project_id))
  use _ <- result.try(checks.area_exists(args.area_id))
  use _ <- result.try(json_transport.execute(payload, True))
  use _ <- result.try(
    verified(checks.verify_area(checks.Project, args.project_id, args.area_id)),
  )
  use _ <- result.try(
    verified(checks.verify_status(checks.Project, args.project_id, status)),
  )
  Ok("Moved project " <> args.project_id <> " to area " <> args.area_id)
}

pub fn handle_remove_todo_from_project(
  args: types.RemoveTodoFromProjectArgs,
) -> Result(String, String) {
  use _ <- result.try(json_payload.validate_id(args.id))
  use output <- result.try(legacy_writes.handle_remove_todo_from_project(args))
  use _ <- result.try(verified(checks.verify_detached(checks.Todo, args.id)))
  Ok(output)
}

pub fn handle_remove_project_from_area(
  args: types.RemoveProjectFromAreaArgs,
) -> Result(String, String) {
  use _ <- result.try(json_payload.validate_id(args.id))
  use output <- result.try(legacy_writes.handle_remove_project_from_area(args))
  use _ <- result.try(verified(checks.verify_detached(checks.Project, args.id)))
  Ok(output)
}
