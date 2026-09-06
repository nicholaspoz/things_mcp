//// Shared input validation for Things writes.

import gleam/int
import gleam/list
import gleam/string

pub fn validate_id(id: String) -> Result(Nil, String) {
  case string.trim(id) {
    "" -> Error("A nonempty Things ID is required")
    _ -> Ok(Nil)
  }
}

/// Validate calendar dates without converting through UTC or a locale-sensitive
/// parser. The original local YYYY-MM-DD value is sent unchanged.
pub fn validate_date(value: String) -> Result(Nil, String) {
  let valid = case string.split(value, "-") {
    [year, month, day] -> {
      case digits(year, 4), digits(month, 2), digits(day, 2) {
        Ok(y), Ok(m), Ok(d) -> {
          let leap = y % 400 == 0 || { y % 4 == 0 && y % 100 != 0 }
          let max_day = case m {
            2 if leap -> 29
            2 -> 28
            4 | 6 | 9 | 11 -> 30
            _ -> 31
          }
          y >= 1 && m >= 1 && m <= 12 && d >= 1 && d <= max_day
        }
        _, _, _ -> False
      }
    }
    _ -> False
  }
  case valid {
    True -> Ok(Nil)
    False ->
      Error("Invalid date; expected a real calendar date in YYYY-MM-DD format")
  }
}

fn digits(value: String, width: Int) -> Result(Int, Nil) {
  case
    string.length(value) == width
    && list.all(string.to_graphemes(value), fn(c) {
      list.contains(["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"], c)
    })
  {
    True -> int.parse(value)
    False -> Error(Nil)
  }
}
