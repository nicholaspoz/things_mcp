# Things3 MCP Server

An MCP (Model Context Protocol) server for interacting with Things3 task manager via AppleScript on macOS.

## Features

### Todo Operations (5 tools)

- **create_todo** - Create a new todo with optional notes, due date, tags, and target list
- **list_todos** - List todos from a specific list (Inbox, Today, Anytime, Upcoming, Someday, Logbook)
- **complete_todo** - Mark a todo as completed
- **update_todo** - Update a todo's properties (name, notes, due date, tags)
- **search_todos** - Search for todos across all lists by name

### Project Operations (3 tools)

- **create_project** - Create a new project with optional notes and area
- **list_projects** - List all projects with optional area filter
- **get_project_todos** - Get all todos within a specific project

### Utility Operations (2 tools)

- **list_tags** - List all available tags
- **list_areas** - List all areas

### Move Operations (6 tools)

- **move_todo** - Move a todo to a built-in list (Today, Anytime, Someday, Logbook, Trash)
- **move_todo_to_project** - Move a todo to a project
- **move_todo_to_area** - Move a todo to an area (removes from project if any)
- **move_project_to_area** - Move a project to an area
- **remove_todo_from_project** - Remove a todo from its project (detach parent)
- **remove_project_from_area** - Remove a project from its area (detach parent)

## Requirements

- macOS (required for AppleScript)
- Things3 installed and running
- Gleam installed (`brew install gleam`)
- Erlang/OTP installed (comes with Gleam)

## Installation

1. Clone or download this repository
2. Build the project:
   ```bash
   cd things_mcp
   gleam build
   ```

## Usage with Claude Desktop

1. Add the server to your Claude Desktop configuration (`~/Library/Application Support/Claude/claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "things3": {
      "type": "stdio",
      "command": "sh",
      "args": ["-c", "cd \"${THINGS_MCP_HOME:-$PWD}\" && exec gleam run 2>/dev/null"]
    }
  }
}
```

2. If your MCP client does not launch the server from this repository directory, set `THINGS_MCP_HOME` to the absolute path of this checkout before starting the client:

```bash
export THINGS_MCP_HOME=/path/to/things_mcp
```

3. Restart Claude Desktop

4. You can now ask Claude to interact with Things3:
   - "Create a todo called 'Buy groceries' in my Inbox"
   - "What todos do I have in Today?"
   - "Mark the 'Buy groceries' todo as complete"
   - "Search for all todos with 'meeting' in the name"
   - "Update the 'Project proposal' todo with a due date of 2026-01-15"
   - "Create a new project called 'Q1 Planning'"
   - "List all projects in my Work area"
   - "Show me all todos in the Q1 Planning project"
   - "What tags do I have?"
   - "List all my areas"
   - "Move the 'Buy groceries' todo to Today"
   - "Move the 'Write report' todo to the Work project"
   - "Move the Budget project to the Home area"
   - "Remove the 'Team meeting' todo from its project"

## Manual Testing

You can test the server manually by running it and sending JSON-RPC messages via stdin:

```bash
gleam run
```

Then send an initialize request (the MCP protocol requires initialization first):

```json
{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "initialize",
  "params": {
    "protocolVersion": "2024-11-05",
    "capabilities": {},
    "clientInfo": { "name": "test", "version": "1.0" }
  }
}
```

Then you can call tools:

```json
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"create_todo","arguments":{"name":"Test Todo","list":"Inbox"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_projects","arguments":{}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"list_tags","arguments":{}}}
```

## Tool Schemas

### create_todo

```json
{
  "name": "Test Todo", // required
  "notes": "Optional notes", // optional
  "due_date": "2026-01-15", // optional (YYYY-MM-DD)
  "tags": ["work", "urgent"], // optional
  "list": "Inbox" // optional (Inbox, Today, Anytime, Someday)
}
```

### list_todos

```json
{
  "location": "Today", // optional (Inbox, Today, Anytime, Upcoming, Someday, Logbook)
  "status": "open" // optional (open, completed, all)
}
```

### complete_todo

```json
{
  "name": "Test Todo" // required
}
```

### update_todo

```json
{
  "name": "Test Todo", // required (current name)
  "new_name": "Updated Todo", // optional
  "new_notes": "New notes", // optional
  "new_due_date": "2026-01-20", // optional (or "none" to clear)
  "new_tags": ["work"] // optional
}
```

### search_todos

```json
{
  "query": "meeting" // required
}
```

### create_project

```json
{
  "name": "Q1 Planning", // required
  "notes": "Optional notes", // optional
  "area": "Work" // optional (area name)
}
```

### list_projects

```json
{
  "area": "Work" // optional (filter by area)
}
```

### get_project_todos

```json
{
  "project": "Q1 Planning", // required
  "status": "open" // optional (open, completed, all)
}
```

### list_tags

```json
{} // no arguments required
```

### list_areas

```json
{} // no arguments required
```

### move_todo

```json
{
  "name": "Test Todo", // required
  "list": "Today" // required (Today, Anytime, Someday, Logbook, Trash)
}
```

### move_todo_to_project

```json
{
  "name": "Test Todo", // required
  "project": "Work Project" // required
}
```

### move_todo_to_area

```json
{
  "name": "Test Todo", // required
  "area": "Home" // required (removes from project if any)
}
```

### move_project_to_area

```json
{
  "name": "My Project", // required
  "area": "Work" // required
}
```

### remove_todo_from_project

```json
{
  "name": "Test Todo" // required
}
```

### remove_project_from_area

```json
{
  "name": "My Project" // required
}
```

## Development

### Project Structure

```
src/
├── things_mcp.gleam             # Main entry point & MCP server setup
├── things_mcp/
│   ├── applescript.gleam       # AppleScript execution layer
│   ├── tools/
│   │   ├── todo_ops.gleam     # Todo tool implementations
│   │   ├── project_ops.gleam  # Project tool implementations
│   │   ├── list_ops.gleam     # List/utility tool implementations
│   │   └── move_ops.gleam     # Move tool implementations
│   └── types.gleam            # Type definitions and decoders
```

### Building

```bash
gleam build
```

### Running

```bash
gleam run
```

### Testing

```bash
gleam test
```

The test suite includes comprehensive integration tests that:
- Test all 16 MCP tools with real Things3 operations
- Use unique `__TEST_*` prefixes to avoid conflicting with user data
- Automatically clean up all test data (even if tests fail)
- Leave no trace in your Things3 database

Test structure:
- `test/integration_test.gleam` - Full integration test covering all 16 tools
- `test/test_helpers/` - State tracking, assertions, and cleanup utilities

## Architecture

The server is built using:

- **mcp_toolkit** (v0.3.1) - MCP protocol implementation
- **shellout** (v1.7) - For executing osascript commands
- **gleam_json** (v3.x) - JSON encoding/decoding
- **gleam/dynamic/decode** - Type-safe argument decoding

The architecture follows a clean separation of concerns:

1. **applescript.gleam** - Low-level AppleScript execution via osascript
2. **types.gleam** - Type definitions, JSON schemas, and decoders for all 16 tools
3. **todo_ops.gleam** - Business logic for todo operations (5 tools)
4. **project_ops.gleam** - Business logic for project operations (3 tools)
5. **list_ops.gleam** - Business logic for utility operations (2 tools)
6. **move_ops.gleam** - Business logic for move operations (6 tools)
7. **things_mcp.gleam** - MCP server assembly and message loop

## Error Handling

The server uses basic error handling that passes through raw AppleScript errors:

- If Things3 is not running: "Application isn't running"
- If a todo is not found: "Can't get to do named..."
- If a date format is invalid: "Can't make date..."

All errors are returned in the MCP response with `is_error: true`.

## Future Enhancements

See the [Things3 developer documentation](https://culturedcode.com/things/support/articles/4562654/) for more information on supported AppleScript commands.

Potential additions (not currently implemented):

- Area operations (create area, get todos in area)
- Tag operations (create tag, manage tag hierarchy)
- Advanced date parsing ("tomorrow", "next week")
- Batch operations (complete multiple todos at once)
- Delete operations (delete todo, delete project)
- Checklist item support (add/remove checklist items)
- Things3 URL scheme integration
- Recurring todo management
