import gleam/io
import gleam/json
import gleam/option.{None, Some}
import mcp_toolkit
import mcp_toolkit/core/protocol as mcp
import mcp_toolkit/transport/stdio
import things_mcp/tools/list_ops
import things_mcp/tools/move_ops
import things_mcp/tools/project_ops
import things_mcp/tools/todo_ops
import things_mcp/types

pub fn main() {
  let server = build_server()

  // Start stdio message loop for MCP communication
  message_loop(server)
}

fn message_loop(server: mcp_toolkit.Server) -> Nil {
  case stdio.read_message() {
    Ok(message) -> {
      case mcp_toolkit.handle_message(server, message) {
        Ok(Some(response)) | Error(response) -> {
          io.println(json.to_string(response))
          message_loop(server)
        }
        Ok(None) -> message_loop(server)
      }
    }
    Error(_) -> Nil
  }
}

fn build_server() -> mcp_toolkit.Server {
  mcp_toolkit.new("things3-mcp", "0.1.0")
  |> mcp_toolkit.description(
    "MCP server for Things3 task manager via AppleScript",
  )
  |> mcp_toolkit.tool_capabilities(True)
  |> mcp_toolkit.prompt_capabilities(False)
  // Register prompts
  |> register_things_inbox_triage_prompt()
  // Register todo tools
  |> register_create_todo()
  |> register_list_todos()
  |> register_get_todo()
  |> register_complete_todo()
  |> register_update_todo()
  |> register_search_todos()
  // Register project tools
  |> register_create_project()
  |> register_list_projects()
  |> register_get_project_todos()
  |> register_complete_project()
  // Register utility tools
  |> register_list_tags()
  |> register_list_areas()
  // Register move tools
  |> register_move_todo()
  |> register_move_todo_to_project()
  |> register_move_todo_to_area()
  |> register_move_project_to_area()
  |> register_remove_todo_from_project()
  |> register_remove_project_from_area()
  |> mcp_toolkit.build()
}

// ===== PROMPT REGISTRATION FUNCTIONS =====

fn register_things_inbox_triage_prompt(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let prompt =
    mcp.Prompt(
      name: "things-inbox-triage",
      description: Some(
        "Review the Things3 Inbox and help decide what to do with each item",
      ),
      arguments: None,
    )

  mcp_toolkit.add_prompt(builder, prompt, handle_things_inbox_triage_prompt)
}

fn handle_things_inbox_triage_prompt(
  _request: mcp.GetPromptRequest,
) -> Result(mcp.GetPromptResult, String) {
  Ok(
    mcp.GetPromptResult(
      meta: None,
      description: Some("Things3 Inbox triage workflow"),
      messages: [
        mcp.PromptMessage(
          role: mcp.User,
          content: mcp.TextPromptContent(mcp.TextContent(
            annotations: None,
            type_: "text",
            text: "Use the Things3 MCP tools to triage my Inbox. First call list_todos with location \"Inbox\" and status \"open\", and provide a brief description of what you found. Then group the results into: quick wins, needs scheduling, should move to a project, and delete or complete candidates. Ask for confirmation before making any changes. When I confirm, use the available Things3 tools to update, complete, move, or create project structure as appropriate.",
          )),
        ),
      ],
    ),
  )
}

// ===== TOOL REGISTRATION FUNCTIONS =====

fn register_create_todo(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.create_todo_schema)

  let tool =
    mcp.Tool(
      name: "create_todo",
      input_schema: schema,
      description: Some(
        "Create a new todo in Things3 with optional notes, due date, tags, and target list",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_create_todo_args(),
    handle_create_todo_wrapper,
  )
}

fn register_list_todos(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.list_todos_schema)

  let tool =
    mcp.Tool(
      name: "list_todos",
      input_schema: schema,
      description: Some(
        "List todos from a specific list in Things3 (Inbox, Today, Anytime, etc.) with optional status filter",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_list_todos_args(),
    handle_list_todos_wrapper,
  )
}

fn register_get_todo(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.get_todo_schema)

  let tool =
    mcp.Tool(
      name: "get_todo",
      input_schema: schema,
      description: Some(
        "Get a todo by stable ID, including the full notes content",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_get_todo_args(),
    handle_get_todo_wrapper,
  )
}

fn register_complete_todo(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.complete_todo_schema)

  let tool =
    mcp.Tool(
      name: "complete_todo",
      input_schema: schema,
      description: Some("Mark a todo as completed in Things3 by stable ID"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_complete_todo_args(),
    handle_complete_todo_wrapper,
  )
}

fn register_complete_project(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.complete_project_schema)

  let tool =
    mcp.Tool(
      name: "complete_project",
      input_schema: schema,
      description: Some(
        "Mark a project as completed in Things3 by stable ID. Things also marks every open todo in the project as completed, so confirm with the user before calling this on a project with open todos.",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_complete_project_args(),
    handle_complete_project_wrapper,
  )
}

fn register_update_todo(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.update_todo_schema)

  let tool =
    mcp.Tool(
      name: "update_todo",
      input_schema: schema,
      description: Some(
        "Update a todo's properties (name, notes, due date, tags) in Things3 by stable ID",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_update_todo_args(),
    handle_update_todo_wrapper,
  )
}

fn register_search_todos(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.search_todos_schema)

  let tool =
    mcp.Tool(
      name: "search_todos",
      input_schema: schema,
      description: Some(
        "Search for todos across Things3 by name and return stable IDs",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_search_todos_args(),
    handle_search_todos_wrapper,
  )
}

// ===== HANDLER WRAPPERS =====
// These wrappers convert between the tool handlers and MCP protocol format

fn handle_create_todo_wrapper(
  request: mcp.CallToolRequest(types.CreateTodoArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case todo_ops.handle_create_todo(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_list_todos_wrapper(
  request: mcp.CallToolRequest(types.ListTodosArgs),
) -> Result(mcp.CallToolResult, String) {
  // Default to empty args if none provided
  let args = case request.arguments {
    Some(a) -> a
    None -> types.ListTodosArgs(location: None, status: None)
  }

  case todo_ops.handle_list_todos(args) {
    Ok(output) ->
      Ok(mcp.CallToolResult(
        meta: None,
        content: [
          mcp.TextToolContent(mcp.TextContent(
            type_: "text",
            text: output,
            annotations: None,
          )),
        ],
        is_error: None,
      ))
    Error(err) ->
      Ok(mcp.CallToolResult(
        meta: None,
        content: [
          mcp.TextToolContent(mcp.TextContent(
            type_: "text",
            text: err,
            annotations: None,
          )),
        ],
        is_error: Some(True),
      ))
  }
}

fn handle_get_todo_wrapper(
  request: mcp.CallToolRequest(types.GetTodoArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case todo_ops.handle_get_todo(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_complete_todo_wrapper(
  request: mcp.CallToolRequest(types.CompleteTodoArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case todo_ops.handle_complete_todo(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_complete_project_wrapper(
  request: mcp.CallToolRequest(types.CompleteProjectArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case project_ops.handle_complete_project(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_update_todo_wrapper(
  request: mcp.CallToolRequest(types.UpdateTodoArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case todo_ops.handle_update_todo(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_search_todos_wrapper(
  request: mcp.CallToolRequest(types.SearchTodosArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case todo_ops.handle_search_todos(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

// ===== PROJECT TOOL REGISTRATION =====

fn register_create_project(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.create_project_schema)

  let tool =
    mcp.Tool(
      name: "create_project",
      input_schema: schema,
      description: Some(
        "Create a new project in Things3 with optional notes and area",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_create_project_args(),
    handle_create_project_wrapper,
  )
}

fn register_list_projects(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.list_projects_schema)

  let tool =
    mcp.Tool(
      name: "list_projects",
      input_schema: schema,
      description: Some("List all projects with optional area filter"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_list_projects_args(),
    handle_list_projects_wrapper,
  )
}

fn register_get_project_todos(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.get_project_todos_schema)

  let tool =
    mcp.Tool(
      name: "get_project_todos",
      input_schema: schema,
      description: Some("Get all todos within a specific project"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_get_project_todos_args(),
    handle_get_project_todos_wrapper,
  )
}

fn register_list_tags(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.list_tags_schema)

  let tool =
    mcp.Tool(
      name: "list_tags",
      input_schema: schema,
      description: Some("List all available tags in Things3"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_list_tags_args(),
    handle_list_tags_wrapper,
  )
}

fn register_list_areas(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.list_areas_schema)

  let tool =
    mcp.Tool(
      name: "list_areas",
      input_schema: schema,
      description: Some("List all areas in Things3"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_list_areas_args(),
    handle_list_areas_wrapper,
  )
}

// ===== PROJECT HANDLER WRAPPERS =====

fn handle_create_project_wrapper(
  request: mcp.CallToolRequest(types.CreateProjectArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case project_ops.handle_create_project(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_list_projects_wrapper(
  request: mcp.CallToolRequest(types.ListProjectsArgs),
) -> Result(mcp.CallToolResult, String) {
  // Default to empty args if none provided
  let args = case request.arguments {
    Some(a) -> a
    None -> types.ListProjectsArgs(area: None)
  }

  case project_ops.handle_list_projects(args) {
    Ok(output) ->
      Ok(mcp.CallToolResult(
        meta: None,
        content: [
          mcp.TextToolContent(mcp.TextContent(
            type_: "text",
            text: output,
            annotations: None,
          )),
        ],
        is_error: None,
      ))
    Error(err) ->
      Ok(mcp.CallToolResult(
        meta: None,
        content: [
          mcp.TextToolContent(mcp.TextContent(
            type_: "text",
            text: err,
            annotations: None,
          )),
        ],
        is_error: Some(True),
      ))
  }
}

fn handle_get_project_todos_wrapper(
  request: mcp.CallToolRequest(types.GetProjectTodosArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case project_ops.handle_get_project_todos(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

// ===== UTILITY HANDLER WRAPPERS =====

fn handle_list_tags_wrapper(
  request: mcp.CallToolRequest(types.ListTagsArgs),
) -> Result(mcp.CallToolResult, String) {
  // No arguments needed
  let args = case request.arguments {
    Some(a) -> a
    None -> types.ListTagsArgs
  }

  case list_ops.handle_list_tags(args) {
    Ok(output) ->
      Ok(mcp.CallToolResult(
        meta: None,
        content: [
          mcp.TextToolContent(mcp.TextContent(
            type_: "text",
            text: output,
            annotations: None,
          )),
        ],
        is_error: None,
      ))
    Error(err) ->
      Ok(mcp.CallToolResult(
        meta: None,
        content: [
          mcp.TextToolContent(mcp.TextContent(
            type_: "text",
            text: err,
            annotations: None,
          )),
        ],
        is_error: Some(True),
      ))
  }
}

fn handle_list_areas_wrapper(
  request: mcp.CallToolRequest(types.ListAreasArgs),
) -> Result(mcp.CallToolResult, String) {
  // No arguments needed
  let args = case request.arguments {
    Some(a) -> a
    None -> types.ListAreasArgs
  }

  case list_ops.handle_list_areas(args) {
    Ok(output) ->
      Ok(mcp.CallToolResult(
        meta: None,
        content: [
          mcp.TextToolContent(mcp.TextContent(
            type_: "text",
            text: output,
            annotations: None,
          )),
        ],
        is_error: None,
      ))
    Error(err) ->
      Ok(mcp.CallToolResult(
        meta: None,
        content: [
          mcp.TextToolContent(mcp.TextContent(
            type_: "text",
            text: err,
            annotations: None,
          )),
        ],
        is_error: Some(True),
      ))
  }
}

// ===== MOVE TOOL REGISTRATION =====

fn register_move_todo(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.move_todo_schema)

  let tool =
    mcp.Tool(
      name: "move_todo",
      input_schema: schema,
      description: Some(
        "Move a todo by stable ID to a built-in list (Today, Anytime, Someday, Logbook, Trash)",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_move_todo_args(),
    handle_move_todo_wrapper,
  )
}

fn register_move_todo_to_project(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let assert Ok(schema) =
    mcp.tool_input_schema(types.move_todo_to_project_schema)

  let tool =
    mcp.Tool(
      name: "move_todo_to_project",
      input_schema: schema,
      description: Some("Move a todo to a project by stable IDs"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_move_todo_to_project_args(),
    handle_move_todo_to_project_wrapper,
  )
}

fn register_move_todo_to_area(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.move_todo_to_area_schema)

  let tool =
    mcp.Tool(
      name: "move_todo_to_area",
      input_schema: schema,
      description: Some(
        "Move a todo to an area by stable IDs (removes from project if currently in one)",
      ),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_move_todo_to_area_args(),
    handle_move_todo_to_area_wrapper,
  )
}

fn register_move_project_to_area(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let assert Ok(schema) =
    mcp.tool_input_schema(types.move_project_to_area_schema)

  let tool =
    mcp.Tool(
      name: "move_project_to_area",
      input_schema: schema,
      description: Some("Move a project to an area by stable IDs"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_move_project_to_area_args(),
    handle_move_project_to_area_wrapper,
  )
}

fn register_remove_todo_from_project(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let assert Ok(schema) =
    mcp.tool_input_schema(types.remove_todo_from_project_schema)

  let tool =
    mcp.Tool(
      name: "remove_todo_from_project",
      input_schema: schema,
      description: Some("Remove a todo from its project by stable ID"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_remove_todo_from_project_args(),
    handle_remove_todo_from_project_wrapper,
  )
}

fn register_remove_project_from_area(
  builder: mcp_toolkit.Builder,
) -> mcp_toolkit.Builder {
  let assert Ok(schema) =
    mcp.tool_input_schema(types.remove_project_from_area_schema)

  let tool =
    mcp.Tool(
      name: "remove_project_from_area",
      input_schema: schema,
      description: Some("Remove a project from its area by stable ID"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_remove_project_from_area_args(),
    handle_remove_project_from_area_wrapper,
  )
}

// ===== MOVE HANDLER WRAPPERS =====

fn handle_move_todo_wrapper(
  request: mcp.CallToolRequest(types.MoveTodoArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case move_ops.handle_move_todo(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_move_todo_to_project_wrapper(
  request: mcp.CallToolRequest(types.MoveTodoToProjectArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case move_ops.handle_move_todo_to_project(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_move_todo_to_area_wrapper(
  request: mcp.CallToolRequest(types.MoveTodoToAreaArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case move_ops.handle_move_todo_to_area(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_move_project_to_area_wrapper(
  request: mcp.CallToolRequest(types.MoveProjectToAreaArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case move_ops.handle_move_project_to_area(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_remove_todo_from_project_wrapper(
  request: mcp.CallToolRequest(types.RemoveTodoFromProjectArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case move_ops.handle_remove_todo_from_project(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}

fn handle_remove_project_from_area_wrapper(
  request: mcp.CallToolRequest(types.RemoveProjectFromAreaArgs),
) -> Result(mcp.CallToolResult, String) {
  case request.arguments {
    Some(args) -> {
      case move_ops.handle_remove_project_from_area(args) {
        Ok(output) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: output,
                annotations: None,
              )),
            ],
            is_error: None,
          ))
        Error(err) ->
          Ok(mcp.CallToolResult(
            meta: None,
            content: [
              mcp.TextToolContent(mcp.TextContent(
                type_: "text",
                text: err,
                annotations: None,
              )),
            ],
            is_error: Some(True),
          ))
      }
    }
    None -> Error("No arguments provided")
  }
}
