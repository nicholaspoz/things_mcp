# Plan: Things3 agent skill

Replace the Gleam/Erlang MCP server with a small local skill. Preserve Inbox triage and the current 17 tools' workflows. This is a plan only; keep the server until the replacement is verified.

## Design

- **Skill:** `SKILL.md` explains commands, ID lookup, supported operations, and result handling.
- **Writes:** Python accepts native Things JSON from stdin or a file, validates it, URL-encodes it, and dispatches the `json` command. Include dry-run. Pydantic is an option for write validation only.
- **Reads:** fixed AppleScript queries run through `osascript`. Foundation's built-in `NSJSONSerialization` produces JSON on stdout for the agent. No PyObjC, JXA, or Python read validation.
- **Inputs:** `osascript reads.applescript "Inbox" "open"` passes strings to `on run argv`. Check arguments and pass values as data, without generating script source.
- **Execution:** Python may invoke `osascript` with `subprocess.run` for one entry point, timeouts, and error handling. Read JSON passes through unchanged; parse it only when needed for internal lookup or write verification.

Use [ThingsJSONCoder](https://github.com/culturedcode/ThingsJSONCoder/blob/master/ThingsJSON.swift) as a reference for Python write models, field names, nesting, and payload fixtures. Cross-check current API documentation and add semantic validation, such as requiring IDs for updates.

## Scope

One row per existing MCP tool, checked against the [server registrations](src/things_mcp.gleam) and [input schemas](src/things_mcp/types.gleam). This covers all 17 tools; runtime parity remains an implementation acceptance check. Read output becomes JSON while preserving the available data.

| Agent operation | Existing MCP tool | Replacement | Required behavior for parity |
| --- | --- | --- | --- |
| Create a task | `create_todo` | JSON create to-do | Title, optional notes/deadline/tags; Inbox (default), Today, Anytime, or Someday; return created ID. |
| List tasks in a built-in list | `list_todos` | AppleScript read | Inbox, Today (default), Anytime, Upcoming, Someday, Logbook; open (default), completed, or all; return IDs, titles, statuses, full notes, deadlines, tags. |
| Read a task | `get_todo` | AppleScript read | Lookup by ID; return title, status, full notes, deadline, and tags. |
| Complete a task | `complete_todo` | JSON update to-do | Set completed by ID; verify status. |
| Update a task | `update_todo` | JSON update to-do | By ID, change title, notes, deadline, or tags; support deadline clearing and empty notes/tags; preserve omitted fields. |
| Search tasks by title | `search_todos` | AppleScript read | Title substring search across Inbox, Today, Anytime, Upcoming, Someday; return IDs, titles, statuses. |
| Create a project | `create_project` | JSON create project | Title, optional notes and area selection by name; return created ID. |
| List projects | `list_projects` | AppleScript read | Optional area-name filter; return IDs, titles, statuses, notes, and area names when listing all projects. |
| List tasks in a project | `get_project_todos` | AppleScript read | Resolve project name; open (default), completed, or all; return task IDs, titles, statuses, full notes, deadlines, tags. |
| List tags | `list_tags` | AppleScript read | Return every tag's ID and name. |
| List areas | `list_areas` | AppleScript read | Return every area's ID and name. |
| Move a task to a built-in list | `move_todo` | JSON `when`; AppleScript for Trash/Logbook | By ID, target Today, Anytime, Someday, Logbook, or Trash; preserve the existing move semantics. |
| Move a task to a project | `move_todo_to_project` | JSON update `list-id` | Resolve task and project by ID; verify project membership. |
| Move a task to an area | `move_todo_to_area` | JSON update `list-id` | Resolve task and area by ID; remove project membership. |
| Move a project to an area | `move_project_to_area` | JSON update `area-id` | Resolve project and area by ID; verify area membership. |
| Detach a task from its project | `remove_todo_from_project` | AppleScript fallback | By task ID, clear project membership without deleting either object. |
| Detach a project from its area | `remove_project_from_area` | AppleScript fallback | By project ID, clear area membership without deleting either object. |

Retain an AppleScript fallback wherever JSON cannot reproduce an existing supported behavior, including tag handling or repeating-item restrictions. The existing Inbox triage prompt becomes skill instructions using these operations.

Later additions: batch operations, reminders, checklists, and project templates with headings. Initially exclude recurrence management, general tag/area administration, private APIs/database access, UI automation, and remote MCP-only clients.

## Implementation

1. Build one parameterized read helper. Check JSON output for Unicode, multiline notes, dates, nulls, and empty collections.
2. Build the Python write runner. Validate payloads, load the authorization token locally, and establish callbacks or read-back verification.
3. Cover current workflows and add the skill instructions. Use stable IDs, distinguish scheduling from deadlines, and preserve omitted versus explicitly cleared fields.
4. Test with disposable Things items, including invalid writes, partial failures, and duplicate names. The existing integration suite mutates Things data.
5. Update the installed Inbox triage skill and disable the MCP registration after parity checks. Retain a rollback path before removing server code.

## Resolve during implementation

- How to receive callbacks and recover created IDs, including nested tasks.
- Which fields can be verified through supported reads; exact clear-field, detach, repeating-item, and Logbook behavior.
- Python dependency installation and whether Pydantic earns its cost.

Report dispatched, verified, failed, and uncertain outcomes distinctly. Do not expose tokens or blindly retry uncertain creates. Preserve notes and local calendar dates; do not silently omit failed reads.

Estimated effort: 2–4 days for a useful hybrid; callback handling and full parity may extend this.

## References

- [Things JSON command](https://culturedcode.com/things/support/articles/2803573/#for-developers)
- [Things AppleScript commands](https://culturedcode.com/things/support/articles/4562654/)
- [Foundation JSON serialization](https://developer.apple.com/documentation/foundation/jsonserialization)
- [Pydantic models](https://docs.pydantic.dev/latest/concepts/models/)
