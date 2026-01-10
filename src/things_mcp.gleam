import gleam/io
import gleam/json
import gleam/option.{None, Some}
import mcp_toolkit
import mcp_toolkit/core/protocol as mcp
import mcp_toolkit/transport/stdio
import things_mcp/tools/list_ops
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
  // Register todo tools
  |> register_create_todo()
  |> register_list_todos()
  |> register_complete_todo()
  |> register_update_todo()
  |> register_search_todos()
  // Register project tools
  |> register_create_project()
  |> register_list_projects()
  |> register_get_project_todos()
  // Register utility tools
  |> register_list_tags()
  |> register_list_areas()
  |> mcp_toolkit.build()
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

fn register_complete_todo(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.complete_todo_schema)

  let tool =
    mcp.Tool(
      name: "complete_todo",
      input_schema: schema,
      description: Some("Mark a todo as completed in Things3 by its name"),
      annotations: None,
    )

  mcp_toolkit.add_tool(
    builder,
    tool,
    types.decode_complete_todo_args(),
    handle_complete_todo_wrapper,
  )
}

fn register_update_todo(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.update_todo_schema)

  let tool =
    mcp.Tool(
      name: "update_todo",
      input_schema: schema,
      description: Some(
        "Update a todo's properties (name, notes, due date, tags) in Things3",
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
      description: Some("Search for todos across all lists in Things3 by name"),
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

fn register_create_project(builder: mcp_toolkit.Builder) -> mcp_toolkit.Builder {
  let assert Ok(schema) = mcp.tool_input_schema(types.create_project_schema)

  let tool =
    mcp.Tool(
      name: "create_project",
      input_schema: schema,
      description: Some("Create a new project in Things3 with optional notes and area"),
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
