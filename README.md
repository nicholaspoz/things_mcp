# Things3 MCP Server

An MCP (Model Context Protocol) server for interacting with Things3 task manager via Things JSON writes and AppleScript on macOS.

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
- Xcode Command Line Tools (`xcode-select --install`) to build the small native URL callback relay

## Installation

1. Clone or download this repository
2. Build the project:
   ```bash
   cd things_mcp
   ./scripts/build_callback.sh
   gleam build
   ```

## Things URL setup

Enable Things URLs in Things → Settings → General → Manage. Copy the authorization token into `~/.config/things-mcp/auth-token`, as the file's sole content, and restrict the file to mode `600`. Alternatively, use the gitignored `.things3_token.txt` in the working directory, or configure `THINGS_AUTH_TOKEN` or `THINGS_AUTH_TOKEN_FILE` in the server's environment. Environment settings take precedence, followed by the working-directory file and then the home-directory file. Never commit a token. Creates do not require a token; JSON updates do.

Gleam encodes and validates the JSON payload and waits for Things' callback, then verifies the result with supported AppleScript reads. The native helper dispatches URLs in the background and receives callback events; it contains no Things write logic. The build produces `build/ThingsCallback.app` and the adjacent `build/ThingsURLDispatch` executable. The callback app starts automatically. Set `THINGS_CALLBACK_APP` to an absolute bundle path when running from another directory, keeping `ThingsURLDispatch` beside the bundle. After rebuilding an already-running relay, quit the `ThingsCallback` process before the next write so macOS loads the new executable.

URL dispatch uses `NSWorkspace.OpenConfiguration.activates = false`. The callback app is registered as background-only, and both native processes prohibit activation. `reveal=false` also prevents navigation to the changed item. Normal writes therefore request background execution; a Things authorization dialog can still require attention. Configure a valid token before live tests and keep invalid-token tests offline.

Callback state is private to the current user under `~/Library/Caches/things-mcp/callbacks`. Authorization URLs are passed through private temporary files rather than process arguments and removed after dispatch. A timeout or failed verification reports uncertain completion; callers must inspect Things before retrying a write.

## Write compatibility

The existing 17 MCP tools, input schemas, handler signatures, and successful response formats are preserved. Creates return stable IDs and writes complete before returning success. Public read tools still use plain AppleScript.

The JSON backend handles task/project creation, ordinary task edits, and moves into projects/areas. Known compatibility cases use AppleScript, selected before any JSON dispatch:

- Existing-item deadline updates, completion, and built-in list moves. Things restricts JSON changes to repeating items, and supported reads cannot reliably identify them. Deadline-bearing updates use AppleScript for the whole operation.
- Detaching tasks from projects or projects from areas.
- Unknown or noncanonical tags, because AppleScript can create tags while JSON ignores missing tags.
- Large text that may exceed JSON field limits. The conservative bounds are 10,000 UTF-8 bytes for notes and 4,000 for titles.

The create fallback explicitly moves scheduled tasks after creation: the old AppleScript `make ... in list "Anytime"` returned an ID while leaving the task in Inbox. Batching and new JSON capabilities remain outside this refactor.

Logbook moves retain the existing AppleScript behavior. In live validation, Things rejected direct moves of both open and completed tasks with error 301; the rejection persists on **Things 3.23.4 (build 32304500)**. This is an observed limitation despite the general AppleScript guide describing Logbook moves. Completion still sets the completed status; the server does not run the global `log completed now` command, which would also affect unrelated tasks.

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

Validated against running **Things 3.23.4 (build 32304500)**: all 24 tests and the native helper self-tests pass. See [IMPLEMENTATION_LOG.md](IMPLEMENTATION_LOG.md) for compatibility decisions and review evidence.

```bash
gleam test
```

The original integration scenario can exceed Gleeunit's default 50-second per-test limit on a populated Things library. Run the same tests with a 180-second budget when needed; this changes only the test runner's limit, not production write timeouts or assertions:

```sh
gleam build
erl -pa build/dev/erlang/*/ebin -noshell -eval 'case eunit:test([integration_test,json_payload_test,json_transport_test,json_write_parity_test], [verbose,{scale_timeouts,36}]) of ok -> halt(0); _ -> halt(1) end.'
```

The test suite includes integration tests that:
- Test all 17 MCP tools with real Things3 operations
- Use unique `__TEST_*` prefixes to avoid conflicting with user data
- Clean up disposable test items after reported failures (tasks are moved to Trash)

Test structure:
- `test/integration_test.gleam` - Full integration test covering all 17 tools
- `test/test_helpers/` - State tracking, assertions, and cleanup utilities
- `test/json_payload_test.gleam` - Pure JSON encoding and validation checks
- `test/json_transport_test.gleam` - Callback, encoding, token-error, and timeout checks
- `test/json_write_parity_test.gleam` - Focused live field, list, container, and fallback checks

## Architecture

The server is built using:

- **mcp_toolkit** (v0.3.1) - MCP protocol implementation
- **shellout** (v1.7) - For executing osascript commands
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
8. **writes.gleam / json_payload.gleam / json_transport.gleam** - Write routing, JSON encoding, and callback results
9. **write_checks.gleam / legacy_writes.gleam** - Dedicated verification reads and compatibility writes
10. **things_json_ffi.erl / native/ThingsCallback.swift** - Bounded OS operations, background URL dispatch, and callback reception

## Error Handling

Validation and target lookup fail before JSON dispatch when possible. Successful callbacks are followed by bounded read-back verification. Callback errors, timeouts, and verification failures never trigger an automatic retry through AppleScript. Errors preserve the MCP `is_error: true` contract and redact transport diagnostics that could include the token.

Run the live suite with local macOS app access and the Things token configured. To run only the focused live parity checks, use `gleam run -m json_write_parity_test`. Pure checks can be run independently after `gleam build`:

```sh
erl -pa build/dev/erlang/*/ebin -noshell -eval 'case eunit:test([json_payload_test, json_transport_test], [verbose]) of ok -> halt(0); _ -> halt(1) end.'
```

## Future Enhancements

See the [Things3 developer documentation](https://culturedcode.com/things/support/articles/4562654/) for more information on supported AppleScript commands.

Potential additions (not currently implemented):

- Area operations (create area, get todos in area)
- Tag operations (create tag, manage tag hierarchy)
- Advanced date parsing ("tomorrow", "next week")
- Batch operations (complete multiple todos at once)
- Delete operations (delete todo, delete project)
- Checklist item support (add/remove checklist items)
- Recurring todo management
