import gleam/list
import gleeunit/should
import things_mcp/validation

pub fn calendar_validation_checks_leap_years_and_strict_format_test() {
  list.each(["2028-02-29", "2000-02-29", "2026-12-31", "0001-01-01"], fn(date) {
    validation.validate_date(date) |> should.equal(Ok(Nil))
  })
  list.each(
    [
      "2026-02-29", "1900-02-29", "2026-04-31", "2026-00-01", "2026-13-01",
      "2026-01-00", "2026-01-32", "0000-01-01", "2026-1-01", "2026-01-1",
      "2026-01-01T00:00:00Z", "2026-01-01\"", "+026-01-01", "２０２６-01-01", "",
    ],
    fn(date) { validation.validate_date(date) |> should.be_error },
  )
}

pub fn ids_must_not_be_blank_test() {
  list.each(["", " ", "\n"], fn(id) {
    validation.validate_id(id) |> should.be_error
  })
  validation.validate_id("task-id") |> should.equal(Ok(Nil))
}
