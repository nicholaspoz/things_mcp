import gleam/io
import gleam/result
import gleam/string

/// Assert that a Result is Ok
pub fn assert_ok(result: Result(a, String), context: String) -> Result(a, String) {
  case result {
    Ok(value) -> {
      io.println("  ✓ " <> context)
      Ok(value)
    }
    Error(err) -> {
      io.println("  ✗ " <> context <> " FAILED")
      io.println("    Error: " <> err)
      Error(context <> ": " <> err)
    }
  }
}

/// Assert that a string contains a substring
pub fn assert_contains(
  haystack: String,
  needle: String,
  context: String,
) -> Result(Nil, String) {
  case string.contains(haystack, needle) {
    True -> {
      io.println("  ✓ " <> context)
      Ok(Nil)
    }
    False -> {
      io.println("  ✗ " <> context <> " FAILED")
      io.println("    Expected to contain: " <> needle)
      io.println("    Got: " <> haystack)
      Error(context <> ": string does not contain expected value")
    }
  }
}

/// Assert that a string does NOT contain a substring
pub fn assert_not_contains(
  haystack: String,
  needle: String,
  context: String,
) -> Result(Nil, String) {
  case string.contains(haystack, needle) {
    False -> {
      io.println("  ✓ " <> context)
      Ok(Nil)
    }
    True -> {
      io.println("  ✗ " <> context <> " FAILED")
      io.println("    Expected NOT to contain: " <> needle)
      io.println("    Got: " <> haystack)
      Error(context <> ": string contains unexpected value")
    }
  }
}

/// Assert that a Result is an Error
pub fn assert_error(result: Result(a, String), context: String) -> Result(Nil, String) {
  case result {
    Error(_) -> {
      io.println("  ✓ " <> context <> " (expected error)")
      Ok(Nil)
    }
    Ok(_) -> {
      io.println("  ✗ " <> context <> " FAILED")
      io.println("    Expected error but got Ok")
      Error(context <> ": expected error but got success")
    }
  }
}

/// Print a test section header
pub fn print_section(title: String) -> Nil {
  io.println("\n=== " <> title <> " ===")
}

/// Print a test phase header
pub fn print_phase(title: String) -> Nil {
  io.println("\n--- " <> title <> " ---")
}

/// Chain result operations
pub fn and_then(
  result: Result(a, String),
  next: fn(a) -> Result(b, String),
) -> Result(b, String) {
  result.try(result, next)
}
