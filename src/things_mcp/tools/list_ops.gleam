import gleam/result
import things_mcp/applescript
import things_mcp/types

// ===== LIST TAGS =====

pub fn handle_list_tags(_args: types.ListTagsArgs) -> Result(String, String) {
  // Build AppleScript to get all tags
  let command =
    "
    set tagList to {}
    repeat with theTag in tags
      try
        set tagID to id of theTag
        set tagName to name of theTag
        set end of tagList to tagID & \" | \" & tagName
      end try
    end repeat
    set AppleScript's text item delimiters to linefeed
    set tagOutput to tagList as text
    set AppleScript's text item delimiters to \"\"
    return tagOutput
  "

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) { "Available tags:\n" <> output })
}

// ===== LIST AREAS =====

pub fn handle_list_areas(_args: types.ListAreasArgs) -> Result(String, String) {
  // Build AppleScript to get all areas
  let command =
    "
    set areaList to {}
    repeat with theArea in areas
      try
        set areaID to id of theArea
        set areaName to name of theArea
        set end of areaList to areaID & \" | \" & areaName
      end try
    end repeat
    set AppleScript's text item delimiters to linefeed
    set areaOutput to areaList as text
    set AppleScript's text item delimiters to \"\"
    return areaOutput
  "

  applescript.execute(applescript.tell_things(command))
  |> result.map(fn(output) { "Available areas:\n" <> output })
}
