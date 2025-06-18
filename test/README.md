# Desiru Minitest Suite

This directory contains Minitest tests for Desiru, providing an alternative to the RSpec test suite.

## Running Minitest

```bash
# Run all Minitest tests
bundle exec rake test

# Run a specific test file
bundle exec ruby test/desiru/module_test.rb

# Run with verbose output
bundle exec ruby test/desiru/module_test.rb -v
```

## Running Both Test Suites

```bash
# Run both RSpec and Minitest
bundle exec rake tests

# Run as part of CI
bundle exec rake ci
```

## Test Structure

- `test_helper.rb` - Common setup and helper methods
- `desiru/` - Tests for core Desiru functionality
  - `basic_test.rb` - Basic functionality tests
  - `module_test.rb` - Module class tests
  - `signature_test.rb` - Signature parsing tests
  - `api/` - API integration tests
  - `persistence/` - Database persistence tests

## Writing Minitest Tests

```ruby
require 'test_helper'

class MyTest < Minitest::Test
  def setup
    # Setup runs before each test
    @module = create_test_module
  end
  
  def test_something
    assert_equal 'expected', @module.call(input: 'test')[:output]
  end
end
```

## Test Helpers

The `test_helper.rb` provides several utilities:

- `create_test_module` - Creates a simple test module with mock model
- `create_mock_model` - Creates a mock LLM model
- `with_mock_model` - Temporarily sets a mock model
- `setup_desiru` - Clears configuration (called automatically)

## Assertions

Minitest provides standard assertions:
- `assert` / `refute`
- `assert_equal` / `refute_equal`
- `assert_nil` / `refute_nil`
- `assert_includes` / `refute_includes`
- `assert_match` / `refute_match`
- `assert_raises`
- `assert_instance_of`
- `assert_kind_of`

## Why Both RSpec and Minitest?

- **Choice** - Developers can use their preferred testing framework
- **Compatibility** - Some projects prefer Minitest's simplicity
- **Rails Integration** - Minitest is Rails' default test framework
- **Learning** - Examples in both frameworks help more developers