# Things3 MCP Server

An MCP (Model Context Protocol) server for interacting with Things3 task manager via AppleScript on macOS.

## Features

### Todo Operations (6 tools)

- **create_todo** - Create a new todo with optional notes, due date, tags, and target list
- **list_todos** - List todos from a specific list (Inbox, Today, Anytime, Upcoming, Someday, Logbook), including stable IDs
- **get_todo** - Get a todo by stable ID, including the full notes content
- **complete_todo** - Mark a todo as completed by stable ID
- **update_todo** - Update a todo's properties (name, notes, due date, tags) by stable ID
- **search_todos** - Search for todos by name and return stable IDs

### Project Operations (3 tools)

- **create_project** - Create a new project with optional notes and area
- **list_projects** - List all projects with optional area filter, including stable IDs
- **get_project_todos** - Get all todos within a specific project, including stable todo IDs

### Utility Operations (2 tools)

- **list_tags** - List all available tags with stable IDs
- **list_areas** - List all areas with stable IDs

### Move Operations (6 tools)

- **move_todo** - Move a todo by stable ID to a built-in list (Today, Anytime, Someday, Logbook, Trash)
- **move_todo_to_project** - Move a todo to a project by stable IDs
- **move_todo_to_area** - Move a todo to an area by stable IDs (removes from project if any)
- **move_project_to_area** - Move a project to an area by stable IDs
- **remove_todo_from_project** - Remove a todo from its project by stable ID
- **remove_project_from_area** - Remove a project from its area by stable ID

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
   - "Show me the full notes for this todo ID"
   - "Find the 'Buy groceries' todo and mark it complete"
   - "Search for all todos with 'meeting' in the name"
   - "Find the 'Project proposal' todo and update it with a due date of 2026-01-15"
   - "Create a new project called 'Q1 Planning'"
   - "List all projects in my Work area"
   - "Show me all todos in the Q1 Planning project"
   - "What tags do I have?"
   - "List all my areas"
   - "Find the 'Buy groceries' todo and move it to Today"
   - "Find the 'Write report' todo and the Work project, then move the todo to that project"
   - "Find the Budget project and Home area, then move the project to the area"
   - "Find the 'Team meeting' todo and remove it from its project"

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

Tools that target existing items use stable Things IDs, not display names. Use `list_todos`, `search_todos`, `list_projects`, and `list_areas` first to get the IDs needed by get, update, complete, move, and detach operations.

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

### get_todo

```json
{
  "id": "abc123" // required (stable todo ID from list_todos or search_todos)
}
```

### complete_todo

```json
{
  "id": "abc123" // required (stable todo ID from list_todos or search_todos)
}
```

### update_todo

```json
{
  "id": "abc123", // required (stable todo ID from list_todos or search_todos)
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
  "id": "abc123", // required (stable todo ID from list_todos or search_todos)
  "list": "Today" // required (Today, Anytime, Someday, Logbook, Trash)
}
```

### move_todo_to_project

```json
{
  "todo_id": "abc123", // required (stable todo ID from list_todos or search_todos)
  "project_id": "def456" // required (stable project ID from list_projects)
}
```

### move_todo_to_area

```json
{
  "todo_id": "abc123", // required (stable todo ID from list_todos or search_todos)
  "area_id": "ghi789" // required (stable area ID from list_areas; removes from project if any)
}
```

### move_project_to_area

```json
{
  "project_id": "def456", // required (stable project ID from list_projects)
  "area_id": "ghi789" // required (stable area ID from list_areas)
}
```

### remove_todo_from_project

```json
{
  "id": "abc123" // required (stable todo ID from list_todos or search_todos)
}
```

### remove_project_from_area

```json
{
  "id": "def456" // required (stable project ID from list_projects)
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

`gleam test` runs offline regression tests. The AppleScript tests require macOS
standard scripting additions but do not contact Things. Run the live suite explicitly:

```bash
gleam run -m integration_test
```

The live suite exercises all 17 handlers using a new UUID namespace per group. It
checks list and container membership, stable IDs, dates, field clearing, Unicode,
multiline and long text, tag creation, case-insensitive tag deduplication, completion,
and status preservation. Cleanup runs even after a handler error or test exception:
fixture tasks and projects go to Trash, and only fixture tags and areas are deleted.
Cleanup is verified; it never empties Trash or invokes global logging. Interrupted
processes may still require manual cleanup using the printed UUID namespace.

The suite does not create repeating templates: the supported AppleScript dictionary
has no recurrence setter. Existing-item edits retain the direct AppleScript path and
do not introduce a repeating-item restriction.

## Architecture

The server is built using:

- **mcp_toolkit** (v0.3.1) - MCP protocol implementation
- **things_applescript_ffi.erl** - Bounded direct osascript subprocess execution
- **gleam_json** (v3.x) - JSON encoding/decoding
- **gleam/dynamic/decode** - Type-safe argument decoding

The architecture follows a clean separation of concerns:

1. **applescript.gleam** - Low-level AppleScript execution via osascript
2. **types.gleam** - Type definitions, JSON schemas, and decoders for all 17 tools
3. **todo_ops.gleam** - Business logic for todo operations (6 tools)
4. **project_ops.gleam** - Business logic for project operations (3 tools)
5. **list_ops.gleam** - Business logic for utility operations (2 tools)
6. **move_ops.gleam** - Business logic for move operations (6 tools)
7. **things_mcp.gleam** - MCP server assembly and message loop

## Error Handling

All errors are returned in the MCP response with `is_error: true`. Successful
response formats and all 17 tool schemas are unchanged.

- Dates must be real `YYYY-MM-DD` calendar dates (including leap-year validation).
  Dates are constructed using local year, month, and day fields, independent of locale.
- Creation explicitly moves the new task into the requested supported list. Writes
  return success only after AppleScript read-back verifies requested fields and
  membership. Updates and container moves also check that status is preserved.
- Omitted fields remain unchanged. `new_notes: ""` and `new_tags: []` clear those
  fields; `new_due_date: "none"` deletes the deadline property. Tag setters retain
  Things' automatic tag creation and case-insensitive canonical-name behavior.
- Writes and ordinary reads have a 10-second subprocess limit. Verification polls
  reads only for up to 3 seconds per check, with a 5-second limit on prerequisite
  reads. Output is capped at 1 MiB. The direct process is killed on timeout; Things
  may still finish an Apple event already delivered to the application.
- Execution failures retain the process exit code and AppleScript error code, with
  safe explanations for common errors (missing objects, conversion, permissions,
  timeouts, or rejected moves). Raw diagnostic text can contain item contents and
  is omitted. Process-start failures and timeouts are reported separately.
- A failed multi-command write can have partially applied changes. Verification
  failures report uncertain completion; errors after successful creation include
  the known created ID. Inspect that item before retrying. Writes are never retried
  automatically; if creation itself times out, an ID may not be available.
- Moving to Logbook uses Things' existing AppleScript move command. It can reject
  the move with code 301, including for completed items on Things 3.23.4. The server
  does not complete items or invoke global logging to force the move.

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
