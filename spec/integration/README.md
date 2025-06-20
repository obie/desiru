# Integration Test Suite

This directory contains integration tests for Desiru, focusing on testing the interactions between components rather than isolated unit behavior.

## Directory Structure

```
spec/integration/
├── README.md (this file)
├── module_composition/     # Tests for combining modules in programs
├── optimizer_workflows/    # Tests for optimization processes
├── async_processing/       # Tests for async and batch operations
├── api_endpoints/          # REST and GraphQL API tests
├── persistence_flows/      # Database integration tests
├── caching_scenarios/      # Cache integration tests
├── error_recovery/         # Failure handling tests
└── examples/              # Real-world usage scenarios
```

## Running Integration Tests

```bash
# Run all integration tests
bundle exec rspec spec/integration

# Run specific category
bundle exec rspec spec/integration/module_composition

# Run with specific tags
bundle exec rspec --tag async spec/integration
bundle exec rspec --tag api spec/integration
```

## Test Guidelines

1. **Setup**: Each test should set up its own data and tear down cleanly
2. **Isolation**: Tests should not depend on other tests
3. **Real APIs**: Use VCR for recording real API interactions
4. **Database**: Use database_cleaner for transaction rollback
5. **Async**: Use helpers to wait for async operations
6. **Timeouts**: Set reasonable timeouts for all async operations

## Common Patterns

### Testing Module Composition
```ruby
let(:program) do
  Desiru::Program.new("name") do
    # Define module pipeline
  end
end
```

### Testing Async Operations
```ruby
include AsyncHelpers

it "processes asynchronously" do
  job = subject.call_async(input)
  wait_for_job(job.id)
  expect(job.reload.status).to eq("completed")
end
```

### Testing with Real LLMs
```ruby
it "works with real API", :vcr do
  # VCR will record/replay API calls
  result = module.call(input)
  expect(result).to be_success
end
```