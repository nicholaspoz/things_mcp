# Plan: Things3 JSON write refactor

Migrate supported writes from AppleScript to Things' JSON developer interface while retaining the Gleam/Erlang MCP server. Keep plain AppleScript for reads. Treat the migration as a refactor: preserve the existing 17 tools, their behavior, and their integration tests wherever possible. Execution status and review evidence are recorded in [IMPLEMENTATION_LOG.md](IMPLEMENTATION_LOG.md).

## Design

- **Agent interface:** preserve MCP registration, tool names, input schemas, handler signatures, and successful response formats, including created IDs. The installed Inbox triage skill continues to use MCP.
- **Writes:** Gleam builds typed Things operations, validates them, encodes JSON and URL parameters, loads the authorization token locally, and dispatches the `json` command through a shared backend for the existing write tools. Keep encoding and validation separate from dispatch so payloads can be tested without changing Things data.
- **Reads:** plain AppleScript queries run through `osascript`, invoked by Gleam. Preserve current read behavior and output during the write refactor.
- **Read helpers:** if extracting queries into `.applescript` files, pass inputs through `on run argv`, validate them, and treat values as data. Keep that extraction separate from write migration; it is not a prerequisite.
- **Execution:** put callback handling, timeouts, ID recovery, and read-back verification behind the write backend. Existing handlers remain synchronous from the caller's perspective: a successful response must mean the operation has completed, so an immediate subsequent read sees the result. Launching a URL alone is not success.
- **Packaging:** no skill replacement, plugin migration, or language/runtime rewrite is needed for this refactor.

Use [ThingsJSONCoder](https://github.com/culturedcode/ThingsJSONCoder/blob/master/ThingsJSON.swift) as a reference for Gleam write types, field names, nesting, and payload fixtures. Cross-check current API documentation and add semantic validation, such as requiring IDs for updates. The Swift implementation is a reference, not a runtime dependency.

## Scope

One row per existing MCP tool, checked against the [server registrations](src/things_mcp.gleam) and [input schemas](src/things_mcp/types.gleam). This covers all 17 tools. Internal write transport changes; existing MCP inputs and outputs remain compatible. The mappings below reflect the implemented backend and compatibility decisions.

| Agent operation | Existing MCP tool | Replacement | Required behavior for parity |
| --- | --- | --- | --- |
| Create a task | `create_todo` | JSON create to-do | Title, optional notes/deadline/tags; Inbox (default), Today, Anytime, or Someday; return created ID. |
| List tasks in a built-in list | `list_todos` | AppleScript read | Inbox, Today (default), Anytime, Upcoming, Someday, Logbook; open (default), completed, or all; return IDs, titles, statuses, full notes, deadlines, tags. |
| Read a task | `get_todo` | AppleScript read | Lookup by ID; return title, status, full notes, deadline, and tags. |
| Complete a task | `complete_todo` | AppleScript compatibility write | Set completed by ID; verify status. |
| Update a task | `update_todo` | JSON update; AppleScript for deadline-bearing updates | By ID, change title, notes, deadline, or tags; support deadline clearing and empty notes/tags; preserve omitted fields. |
| Search tasks by title | `search_todos` | AppleScript read | Title substring search across Inbox, Today, Anytime, Upcoming, Someday; return IDs, titles, statuses. |
| Create a project | `create_project` | JSON create project | Title, optional notes and area selection by name; return created ID. |
| List projects | `list_projects` | AppleScript read | Optional area-name filter; return IDs, titles, statuses, notes, and area names when listing all projects. |
| List tasks in a project | `get_project_todos` | AppleScript read | Resolve project name; open (default), completed, or all; return task IDs, titles, statuses, full notes, deadlines, tags. |
| List tags | `list_tags` | AppleScript read | Return every tag's ID and name. |
| List areas | `list_areas` | AppleScript read | Return every area's ID and name. |
| Move a task to a built-in list | `move_todo` | AppleScript compatibility write | By ID, target Today, Anytime, Someday, Logbook, or Trash; preserve the existing move semantics. |
| Move a task to a project | `move_todo_to_project` | JSON update `list-id` | Resolve task and project by ID; verify project membership. |
| Move a task to an area | `move_todo_to_area` | JSON update `list-id` | Resolve task and area by ID; remove project membership. |
| Move a project to an area | `move_project_to_area` | JSON update `area-id` | Resolve project and area by ID; verify area membership. |
| Detach a task from its project | `remove_todo_from_project` | AppleScript fallback | By task ID, clear project membership without deleting either object. |
| Detach a project from its area | `remove_project_from_area` | AppleScript fallback | By project ID, clear area membership without deleting either object. |

Retain an AppleScript fallback wherever JSON cannot reproduce an existing supported behavior, including tag handling or repeating-item restrictions. Select fallbacks for known unsupported cases before dispatch; never retry an uncertain JSON write through AppleScript. Keep the existing Inbox triage skill using the same MCP tools.

Implementation review found that Things restricts JSON updates to repeating items, while supported reads expose neither recurrence metadata nor a Repeating list. Preserve feature parity by preselecting AppleScript for existing-item scheduling, completion, and deadline-bearing updates. Creates can still use JSON scheduling/deadlines. Ordinary edits and container moves use JSON with read-back verification. Unknown/noncanonical tags and large text also select compatibility writes before dispatch. These fallbacks are deliberate; no uncertain JSON result triggers a second write.

Batching and additional JSON functionality (reminders, checklists, and project templates with headings) are optional follow-ups after the feature-parity refactor is complete. They impose no implementation, API, or test requirements on this refactor.

Exclude recurrence management, general tag/area administration, private APIs/database access, UI automation, and new remote hosting from this work. Preserve existing MCP client compatibility.

## Implementation

1. Establish a baseline with the existing integration suite and record pre-existing failures. Identify the handler inputs, response formats, and immediate-read expectations it exercises. Leave production read code and the test harness in place.
2. Build the shared Gleam JSON encoder, validator, and dispatcher. Resolve authorization, callbacks, created-ID recovery, and bounded completion/verification before switching handlers. Prove one create and one update with disposable items.
3. Migrate write handlers incrementally through the shared backend, preserving signatures, response formats, stable IDs, scheduling versus deadlines, and omitted versus explicitly cleared fields. Keep documented fallbacks for unsupported operations.
4. Run the existing integration suite against migrated handlers. Add focused tests for transport-specific risks and behavior not covered by the baseline; do not rewrite existing expectations to accommodate regressions.
5. Remove obsolete AppleScript write code only after parity is verified; retain necessary fallbacks and the MCP registration.

## Test compatibility

- Target zero changes to existing integration test calls and assertions. The suite calls Gleam handlers directly, checks created responses for `ID:`, and reads state immediately after mutations; preserve all three contracts.
- Keep waiting and verification inside production write code. Do not add sleeps or polling to existing tests to hide asynchronous dispatch behavior.
- The Things URL authorization token is new environment setup, not a reason to change the tool signatures or pass secrets through test arguments.
- Existing tests are a regression baseline, not proof of full parity: some assertions check only success/text, and edge-case assertion results are currently discarded. If needed, fix assertion propagation narrowly without changing expected behavior.
- Add tests for JSON encoding and escaping, Unicode/multiline notes, dates, omitted/cleared fields, invalid IDs, authorization failures, timeout/uncertain results, and duplicate names.
- Integration tests mutate real Things data and use disposable test items with cleanup.

## Resolved implementation decisions

- A small native background app receives nonce-scoped callbacks and publishes private result files. Gleam decodes the created ID; name matching is never used for recovery. A separate native executable dispatches URLs without activating Things or competing for callback registration.
- Supported AppleScript reads verify changed fields, status and destination membership. Direct ID references resolve newly created items. Deadline clearing and detach use property deletion. Recurrence-sensitive writes retain AppleScript. Direct Logbook moves retain the original error behavior observed in Things; no global logging operation is substituted.
- Load authorization from the configured environment, the gitignored working-directory token file, or the home-directory configuration file. Token-bearing URLs stay out of process arguments and diagnostic output; the README documents precedence and setup.
- Dispatch, callback waiting and read verification are bounded separately. Successful JSON writes require a valid callback and verified state. Unknown tags and large text select compatibility writes before dispatch. No failed or uncertain JSON write is retried automatically.

Distinguish dispatched, completed/verified, failed, and uncertain outcomes internally. Preserve existing successful response formats; return a clear error for uncertain completion instead of claiming success. Do not expose tokens or blindly retry uncertain writes. Preserve notes and local calendar dates; do not silently omit failed reads used for verification.

The callback and ID-recovery proof of concept, handler migration, focused adversarial reviews, and live parity checks are recorded in [IMPLEMENTATION_LOG.md](IMPLEMENTATION_LOG.md).

## References

- [Things JSON command](https://culturedcode.com/things/support/articles/2803573/#for-developers)
- [Things AppleScript commands](https://culturedcode.com/things/support/articles/4562654/)
- [ThingsJSONCoder reference](https://github.com/culturedcode/ThingsJSONCoder/blob/master/ThingsJSON.swift)
