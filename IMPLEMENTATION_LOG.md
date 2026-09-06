# Things JSON write refactor execution

## Workflow

Implement one narrow stage, request an independent adversarial review, address concrete findings, then validate before advancing. Keep feature additions and batching out of scope.

## Stages

1. Commit plan and establish baseline — plan committed as `48a0c24`.
2. Pure Gleam payloads and callback transport — committed as `71c99c5`; independent reviews complete, 19 focused tests pass.
3. Create/update/complete handlers with public AppleScript verification — committed in `be91d6e`; independent reviews and live create/edit/clear/completion and fallback boundary checks pass.
4. Move handlers and documented compatibility fallbacks — committed in `be91d6e`; original integration test and corrected container/Logbook parity checks pass.
5. Full compatibility checks, documentation, and final review — complete. All 24 tests pass, including a full rerun after the user's upgrade to Things 3.23.4. Background dispatch committed as `993e6ae`; independent review and monitored live checks pass.

## Final validation after the Things upgrade

- Installed and running version: Things **3.23.4**, build **32304500**, verified on 2026-09-06.
- All **24 tests passed** in one combined EUnit run using the documented 180-second per-test budget. Native callback/dispatch self-tests also passed.
- A 45-second foreground monitor covering the upgraded-app parity checks recorded no app changes; Codex remained active.
- The original integration test, its helper files, and all 17 tool schemas remain unchanged from the committed plan baseline.
- Updated public scripting definitions still expose no recurrence property. Current [URL documentation](https://culturedcode.com/things/support/articles/2803573/) retains repeating-item restrictions and ignores unknown JSON tags. The [release notes](https://culturedcode.com/things/support/articles/1100684/) provide no documented interface change requiring a different fallback policy.
- Runtime tests on 3.23.4 confirm deadline clearing, tag/text fallbacks, status preservation, container moves, detachment, and the existing direct-Logbook-move rejection. Keep Logbook behavior documented as an observed version-specific limitation rather than a universal API rule.
- Batching, new tools and expanded JSON functionality remain deferred. No implementation change was needed for this upgrade.

## Baseline evidence

- Original `gleam test` cannot access macOS app services inside the sandbox; run integration tests with local app access.
- Outside the sandbox, the original suite passes through phase 5, then fails looking up its third task in Anytime.
- Isolated reproduction confirms `make new to do in list "Anytime"` creates an Inbox task. JSON `when: "anytime"` places it in Anytime correctly.
- The old AppleScript `tag names` setter creates missing tags; JSON ignores unknown tags. Preserve this with a known-case fallback selected before dispatch.
- Public Things AppleScript has no recurrence property, and `list "Repeating"` returns -1728. Do not use private Things APIs to infer recurrence.

## Reviewed transport evidence

- Pure payload tests cover calendar validation, field clearing/omission, Unicode, list mappings, IDs and destinations.
- Native relay self-tests cover malformed callbacks, duplicate keys, expired/unknown requests, symlinks and atomic first-result publication.
- Runtime review found and fixed direct subprocesses surviving timeout and malformed UTF-8 token configuration raising exceptions.
- Live create callback returned the correct stable ID; immediate AppleScript read verified title and Anytime membership. Disposable item cleaned up.
- Native helper uses AppKit for background URL dispatch and callback reception. Gleam owns payloads, validation, URL construction, result decoding and verification; Erlang FFI provides bounded process/file operations.

## Environment and live-test findings

- The user supplied the token in the gitignored `.things3_token.txt`; authenticated JSON updates work. The token stays out of logs and process arguments.
- Invalid-token live tests triggered a Things authorization dialog. They were removed; malformed token-file coverage remains offline.
- AppleScript `open location` activated Things despite `reveal=false`. Native `NSWorkspace` dispatch now requests `activates=false`. A first live check caught the accessory callback app taking focus; the relay now uses `LSBackgroundOnly` and the dispatcher runs outside its app bundle. The revised create/update smoke test passed with no foreground-app changes (Music remained active throughout).
- Public predicate-based ID lookups missed freshly JSON-created items. Direct `to do id` and `project id` references resolve them, and the public accessors now use these references.
- Fixture cleanup materializes property lists before iterating, then checks that its UUID-scoped fixtures are absent from active lists. Cleanup never targets unrelated names.
- Locale-based AppleScript date parsing reinterpreted an ISO deadline. Explicit local calendar construction and post-write verification replace that parser. Independent read-only checks cover leap days, leading zeros, and local DST transitions.
- Deadline clearing failed because Things rejects assigning `missing value` or an empty string to its date property. `delete due date` clears it, is idempotent, and leaves the item intact; verified on the failing disposable fixture.

## Compatibility decisions

- Preserve existing integration test source unchanged. New tests independently cover IDs, omitted/cleared fields, dates, text, tags, list membership, parent survival, and status preservation.
- Keep existing-item completion, scheduling and deadline-bearing updates on AppleScript because there is no supported recurrence preflight. Do not dispatch JSON and then retry through AppleScript.
- Unknown/noncanonical tags and potentially over-limit text also select AppleScript before dispatch. Conservative byte bounds avoid undercounting Unicode characters.
- Live tag/long-note tests pass for unknown tag create/replacement and 10,000/10,001-character notes on task create/update and project create.
- The original integration test passes unchanged. The new container test initially expected direct Logbook moves to succeed. Isolated tests of the original AppleScript command returned error 301 for both open and completed tasks, with state unchanged. The new test preserves these rejections and verifies completed-task movement to Trash. Do not invoke the global logging command to force success.
- A subsequent run exceeded Gleeunit's default 50-second per-test limit during an existing AppleScript search in the original integration test. Final validation uses the same test modules and assertions with EUnit's timeout scale set to 36 (180 seconds per test). Production process and verification limits remain unchanged.
- Global Things task lookup excludes Trash; list-membership verification now queries the target list directly. Live completion and Trash verification pass.
- URL round-trip tests exposed literal plus signs being interpreted as spaces; query encoding now explicitly escapes `+` as `%2B`.
