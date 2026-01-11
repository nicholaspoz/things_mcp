import gleam/dynamic/decode
import gleam/option.{type Option}

// ===== CREATE TODO =====

pub type CreateTodoArgs {
  CreateTodoArgs(
    name: String,
    notes: Option(String),
    due_date: Option(String),
    tags: Option(List(String)),
    list: Option(String),
  )
}

pub fn decode_create_todo_args() -> decode.Decoder(CreateTodoArgs) {
  use name <- decode.field("name", decode.string)
  use notes <- decode.field("notes", decode.optional(decode.string))
  use due_date <- decode.field("due_date", decode.optional(decode.string))
  use tags <- decode.field("tags", decode.optional(decode.list(decode.string)))
  use list <- decode.field("list", decode.optional(decode.string))
  decode.success(CreateTodoArgs(
    name: name,
    notes: notes,
    due_date: due_date,
    tags: tags,
    list: list,
  ))
}

pub const create_todo_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"The name of the todo\"
    },
    \"notes\": {
      \"type\": \"string\",
      \"description\": \"Optional notes for the todo\"
    },
    \"due_date\": {
      \"type\": \"string\",
      \"description\": \"Optional due date in YYYY-MM-DD format\"
    },
    \"tags\": {
      \"type\": \"array\",
      \"items\": {
        \"type\": \"string\"
      },
      \"description\": \"Optional list of tag names\"
    },
    \"list\": {
      \"type\": \"string\",
      \"enum\": [\"Inbox\", \"Today\", \"Anytime\", \"Someday\"],
      \"description\": \"Target list (default: Inbox)\"
    }
  },
  \"required\": [\"name\"]
}"

// ===== LIST TODOS =====

pub type ListTodosArgs {
  ListTodosArgs(location: Option(String), status: Option(String))
}

pub fn decode_list_todos_args() -> decode.Decoder(ListTodosArgs) {
  use location <- decode.field("location", decode.optional(decode.string))
  use status <- decode.field("status", decode.optional(decode.string))
  decode.success(ListTodosArgs(location: location, status: status))
}

pub const list_todos_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"location\": {
      \"type\": \"string\",
      \"enum\": [\"Inbox\", \"Today\", \"Anytime\", \"Upcoming\", \"Someday\", \"Logbook\"],
      \"description\": \"Which list to retrieve todos from (default: Today)\"
    },
    \"status\": {
      \"type\": \"string\",
      \"enum\": [\"open\", \"completed\", \"all\"],
      \"description\": \"Filter by status (default: open)\"
    }
  }
}"

// ===== COMPLETE TODO =====

pub type CompleteTodoArgs {
  CompleteTodoArgs(name: String)
}

pub fn decode_complete_todo_args() -> decode.Decoder(CompleteTodoArgs) {
  use name <- decode.field("name", decode.string)
  decode.success(CompleteTodoArgs(name: name))
}

pub const complete_todo_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"Name of the todo to mark as complete\"
    }
  },
  \"required\": [\"name\"]
}"

// ===== UPDATE TODO =====

pub type UpdateTodoArgs {
  UpdateTodoArgs(
    name: String,
    new_name: Option(String),
    new_notes: Option(String),
    new_due_date: Option(String),
    new_tags: Option(List(String)),
  )
}

pub fn decode_update_todo_args() -> decode.Decoder(UpdateTodoArgs) {
  use name <- decode.field("name", decode.string)
  use new_name <- decode.field("new_name", decode.optional(decode.string))
  use new_notes <- decode.field("new_notes", decode.optional(decode.string))
  use new_due_date <- decode.field(
    "new_due_date",
    decode.optional(decode.string),
  )
  use new_tags <- decode.field(
    "new_tags",
    decode.optional(decode.list(decode.string)),
  )
  decode.success(UpdateTodoArgs(
    name: name,
    new_name: new_name,
    new_notes: new_notes,
    new_due_date: new_due_date,
    new_tags: new_tags,
  ))
}

pub const update_todo_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"Current name of the todo to update\"
    },
    \"new_name\": {
      \"type\": \"string\",
      \"description\": \"New name for the todo\"
    },
    \"new_notes\": {
      \"type\": \"string\",
      \"description\": \"New notes for the todo\"
    },
    \"new_due_date\": {
      \"type\": \"string\",
      \"description\": \"New due date in YYYY-MM-DD format, or 'none' to clear\"
    },
    \"new_tags\": {
      \"type\": \"array\",
      \"items\": {
        \"type\": \"string\"
      },
      \"description\": \"New list of tag names\"
    }
  },
  \"required\": [\"name\"]
}"

// ===== SEARCH TODOS =====

pub type SearchTodosArgs {
  SearchTodosArgs(query: String)
}

pub fn decode_search_todos_args() -> decode.Decoder(SearchTodosArgs) {
  use query <- decode.field("query", decode.string)
  decode.success(SearchTodosArgs(query: query))
}

pub const search_todos_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"query\": {
      \"type\": \"string\",
      \"description\": \"Search term to match in todo names\"
    }
  },
  \"required\": [\"query\"]
}"

// ===== CREATE PROJECT =====

pub type CreateProjectArgs {
  CreateProjectArgs(name: String, notes: Option(String), area: Option(String))
}

pub fn decode_create_project_args() -> decode.Decoder(CreateProjectArgs) {
  use name <- decode.field("name", decode.string)
  use notes <- decode.field("notes", decode.optional(decode.string))
  use area <- decode.field("area", decode.optional(decode.string))
  decode.success(CreateProjectArgs(name: name, notes: notes, area: area))
}

pub const create_project_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"The name of the project\"
    },
    \"notes\": {
      \"type\": \"string\",
      \"description\": \"Optional notes for the project\"
    },
    \"area\": {
      \"type\": \"string\",
      \"description\": \"Optional area name to assign the project to\"
    }
  },
  \"required\": [\"name\"]
}"

// ===== LIST PROJECTS =====

pub type ListProjectsArgs {
  ListProjectsArgs(area: Option(String))
}

pub fn decode_list_projects_args() -> decode.Decoder(ListProjectsArgs) {
  use area <- decode.field("area", decode.optional(decode.string))
  decode.success(ListProjectsArgs(area: area))
}

pub const list_projects_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"area\": {
      \"type\": \"string\",
      \"description\": \"Optional area name to filter projects by\"
    }
  }
}"

// ===== GET PROJECT TODOS =====

pub type GetProjectTodosArgs {
  GetProjectTodosArgs(project: String, status: Option(String))
}

pub fn decode_get_project_todos_args() -> decode.Decoder(GetProjectTodosArgs) {
  use project <- decode.field("project", decode.string)
  use status <- decode.field("status", decode.optional(decode.string))
  decode.success(GetProjectTodosArgs(project: project, status: status))
}

pub const get_project_todos_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"project\": {
      \"type\": \"string\",
      \"description\": \"The name of the project\"
    },
    \"status\": {
      \"type\": \"string\",
      \"enum\": [\"open\", \"completed\", \"all\"],
      \"description\": \"Filter by status (default: open)\"
    }
  },
  \"required\": [\"project\"]
}"

// ===== LIST TAGS =====

pub type ListTagsArgs {
  ListTagsArgs
}

pub fn decode_list_tags_args() -> decode.Decoder(ListTagsArgs) {
  decode.success(ListTagsArgs)
}

pub const list_tags_schema = "{
  \"type\": \"object\",
  \"properties\": {}
}"

// ===== LIST AREAS =====

pub type ListAreasArgs {
  ListAreasArgs
}

pub fn decode_list_areas_args() -> decode.Decoder(ListAreasArgs) {
  decode.success(ListAreasArgs)
}

pub const list_areas_schema = "{
  \"type\": \"object\",
  \"properties\": {}
}"

// ===== MOVE TODO =====

pub type MoveTodoArgs {
  MoveTodoArgs(name: String, list: String)
}

pub fn decode_move_todo_args() -> decode.Decoder(MoveTodoArgs) {
  use name <- decode.field("name", decode.string)
  use list <- decode.field("list", decode.string)
  decode.success(MoveTodoArgs(name: name, list: list))
}

pub const move_todo_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"Name of the todo to move\"
    },
    \"list\": {
      \"type\": \"string\",
      \"enum\": [\"Today\", \"Anytime\", \"Someday\", \"Logbook\", \"Trash\"],
      \"description\": \"Target list to move the todo to\"
    }
  },
  \"required\": [\"name\", \"list\"]
}"

// ===== MOVE TODO TO PROJECT =====

pub type MoveTodoToProjectArgs {
  MoveTodoToProjectArgs(name: String, project: String)
}

pub fn decode_move_todo_to_project_args() -> decode.Decoder(
  MoveTodoToProjectArgs,
) {
  use name <- decode.field("name", decode.string)
  use project <- decode.field("project", decode.string)
  decode.success(MoveTodoToProjectArgs(name: name, project: project))
}

pub const move_todo_to_project_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"Name of the todo to move\"
    },
    \"project\": {
      \"type\": \"string\",
      \"description\": \"Name of the project to move the todo to\"
    }
  },
  \"required\": [\"name\", \"project\"]
}"

// ===== MOVE TODO TO AREA =====

pub type MoveTodoToAreaArgs {
  MoveTodoToAreaArgs(name: String, area: String)
}

pub fn decode_move_todo_to_area_args() -> decode.Decoder(MoveTodoToAreaArgs) {
  use name <- decode.field("name", decode.string)
  use area <- decode.field("area", decode.string)
  decode.success(MoveTodoToAreaArgs(name: name, area: area))
}

pub const move_todo_to_area_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"Name of the todo to move\"
    },
    \"area\": {
      \"type\": \"string\",
      \"description\": \"Name of the area to move the todo to (will remove from project if any)\"
    }
  },
  \"required\": [\"name\", \"area\"]
}"

// ===== MOVE PROJECT TO AREA =====

pub type MoveProjectToAreaArgs {
  MoveProjectToAreaArgs(name: String, area: String)
}

pub fn decode_move_project_to_area_args() -> decode.Decoder(
  MoveProjectToAreaArgs,
) {
  use name <- decode.field("name", decode.string)
  use area <- decode.field("area", decode.string)
  decode.success(MoveProjectToAreaArgs(name: name, area: area))
}

pub const move_project_to_area_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"Name of the project to move\"
    },
    \"area\": {
      \"type\": \"string\",
      \"description\": \"Name of the area to move the project to\"
    }
  },
  \"required\": [\"name\", \"area\"]
}"

// ===== REMOVE TODO FROM PROJECT =====

pub type RemoveTodoFromProjectArgs {
  RemoveTodoFromProjectArgs(name: String)
}

pub fn decode_remove_todo_from_project_args() -> decode.Decoder(
  RemoveTodoFromProjectArgs,
) {
  use name <- decode.field("name", decode.string)
  decode.success(RemoveTodoFromProjectArgs(name: name))
}

pub const remove_todo_from_project_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"Name of the todo to remove from its project\"
    }
  },
  \"required\": [\"name\"]
}"

// ===== REMOVE PROJECT FROM AREA =====

pub type RemoveProjectFromAreaArgs {
  RemoveProjectFromAreaArgs(name: String)
}

pub fn decode_remove_project_from_area_args() -> decode.Decoder(
  RemoveProjectFromAreaArgs,
) {
  use name <- decode.field("name", decode.string)
  decode.success(RemoveProjectFromAreaArgs(name: name))
}

pub const remove_project_from_area_schema = "{
  \"type\": \"object\",
  \"properties\": {
    \"name\": {
      \"type\": \"string\",
      \"description\": \"Name of the project to remove from its area\"
    }
  },
  \"required\": [\"name\"]
}"
