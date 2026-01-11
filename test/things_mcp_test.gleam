import gleeunit
import integration_test

pub fn main() -> Nil {
  gleeunit.main()
}

// Run the full integration test suite
// This tests all 16 MCP tools and cleans up after itself
pub fn full_integration_test() {
  integration_test.full_integration_test()
}
