# Desiru Integration Test Strategy

## Overview

This document outlines a comprehensive integration testing strategy for Ruby DSPy (Desiru). The focus is on testing the integration points between components rather than unit testing individual classes in isolation.

## Test Categories

### 1. Module Composition Tests

#### 1.1 Simple Module Pipelines
- **Test**: Chain multiple modules together (Predict → ChainOfThought → ReAct)
- **Verification**: Output of one module correctly feeds into the next
- **Edge Cases**: Null outputs, malformed responses, type mismatches

#### 1.2 Complex Program Construction
- **Test**: Programs with conditional module execution
- **Verification**: Correct module selection based on input conditions
- **Edge Cases**: Circular dependencies, missing modules, invalid configurations

#### 1.3 Module + Retrieve Integration
- **Test**: Modules that use retrieval for context augmentation
- **Verification**: Retrieved context properly integrated into prompts
- **Edge Cases**: Empty retrieval results, timeout scenarios, large result sets

### 2. Optimizer Integration Tests

#### 2.1 BootstrapFewShot with Different Modules
- **Test**: Optimize Predict, ChainOfThought, and ReAct modules
- **Verification**: Improved performance metrics after optimization
- **Edge Cases**: Insufficient training data, conflicting examples, overfitting

#### 2.2 Optimizer + Persistence
- **Test**: Save and restore optimized module states
- **Verification**: Optimized modules maintain performance after reload
- **Edge Cases**: Corrupted state, version mismatches, concurrent updates

#### 2.3 Multi-Module Optimization
- **Test**: Optimize programs with multiple interconnected modules
- **Verification**: All modules improve without degrading others
- **Edge Cases**: Module interdependencies, shared parameters

### 3. Async Processing Tests

#### 3.1 Async Module Execution
- **Test**: Execute modules asynchronously with result tracking
- **Verification**: Job status updates, result retrieval, error propagation
- **Edge Cases**: Job timeouts, Redis failures, worker crashes

#### 3.2 Batch Processing
- **Test**: Process multiple inputs concurrently
- **Verification**: Correct result ordering, partial failure handling
- **Edge Cases**: Mixed sync/async operations, rate limiting

#### 3.3 Async + Persistence
- **Test**: Persist async job results and status updates
- **Verification**: Database consistency, transaction handling
- **Edge Cases**: Concurrent writes, database connection failures

### 4. API Integration Tests

#### 4.1 REST API End-to-End
- **Test**: Full request/response cycle through Sinatra/Grape
- **Verification**: Parameter validation, response formatting, error handling
- **Edge Cases**: Invalid inputs, authentication failures, CORS issues

#### 4.2 GraphQL Module Execution
- **Test**: Execute Desiru modules via GraphQL queries
- **Verification**: Schema generation, type safety, resolver execution
- **Edge Cases**: Deeply nested queries, circular references, N+1 queries

#### 4.3 SSE Streaming
- **Test**: Stream module execution progress via Server-Sent Events
- **Verification**: Event formatting, connection handling, graceful disconnects
- **Edge Cases**: Client disconnections, slow consumers, buffer overflows

### 5. Caching Integration Tests

#### 5.1 Module Result Caching
- **Test**: Cache module outputs with TTL
- **Verification**: Cache hits/misses, expiration handling
- **Edge Cases**: Cache stampede, memory limits, Redis failures

#### 5.2 Optimizer Caching
- **Test**: Cache optimization computations
- **Verification**: Cached optimizer state validity
- **Edge Cases**: Stale cache with updated training data

### 6. Error Handling and Recovery Tests

#### 6.1 LLM Provider Failures
- **Test**: Handle API errors from OpenAI/Anthropic
- **Verification**: Retry logic, fallback behavior, error propagation
- **Edge Cases**: Rate limits, timeout, malformed responses

#### 6.2 Persistence Failures
- **Test**: Database connection issues during operation
- **Verification**: Transaction rollback, data integrity
- **Edge Cases**: Partial writes, deadlocks, connection pool exhaustion

#### 6.3 Async Job Failures
- **Test**: Worker crashes, Redis unavailability
- **Verification**: Job retry, dead letter queue, notification webhooks
- **Edge Cases**: Poison messages, infinite retry loops

## Test Implementation Plan

### Phase 1: Core Integration Tests (Weeks 1-2)
1. Module composition tests
2. Basic optimizer integration
3. Sync execution paths

### Phase 2: Async and Persistence (Weeks 3-4)
1. Async module execution
2. Batch processing
3. Persistence integration
4. Job failure handling

### Phase 3: API Integration (Weeks 5-6)
1. REST API workflows
2. GraphQL integration
3. SSE streaming
4. Authentication/authorization

### Phase 4: Advanced Scenarios (Weeks 7-8)
1. Complex program optimization
2. Multi-tenant scenarios
3. Performance and load testing
4. Chaos engineering tests

## Test Infrastructure

### Required Test Fixtures
```ruby
# spec/support/integration_helpers.rb
module IntegrationHelpers
  def setup_test_program
    # Create a multi-module program for testing
  end

  def setup_test_data
    # Create training examples, retrieval corpus
  end

  def stub_llm_responses
    # Predictable LLM responses for testing
  end
end
```

### Database Setup
```ruby
# spec/support/database_cleaner.rb
RSpec.configure do |config|
  config.before(:each, type: :integration) do
    DatabaseCleaner.strategy = :transaction
  end
end
```

### Async Test Support
```ruby
# spec/support/async_helpers.rb
module AsyncHelpers
  def wait_for_job(job_id, timeout: 5)
    # Helper to wait for async job completion
  end
end
```

## Success Criteria

1. **Coverage**: All major integration points have tests
2. **Reliability**: Tests run consistently without flakiness
3. **Performance**: Integration tests complete within 10 minutes
4. **Maintainability**: Clear test organization and documentation
5. **Real-world**: Tests reflect actual usage patterns

## Example Integration Test Structure

```ruby
RSpec.describe "Module Composition Integration", type: :integration do
  describe "Predict → ChainOfThought → ReAct pipeline" do
    let(:program) do
      Desiru::Program.new("Question Answering System") do
        predict = Desiru::Predict.new(signature: "question -> initial_answer")
        cot = Desiru::ChainOfThought.new(signature: "initial_answer -> reasoning")
        react = Desiru::ReAct.new(signature: "reasoning -> final_answer", tools: [Calculator, WebSearch])
        
        compose(predict, cot, react)
      end
    end

    it "processes complex questions through all modules" do
      result = program.call(question: "What is the population of Tokyo multiplied by 2?")
      
      expect(result.final_answer).to match(/approximately.*million/)
      expect(result.intermediate_results).to include(
        have_attributes(module: "Predict", status: "completed"),
        have_attributes(module: "ChainOfThought", status: "completed"),
        have_attributes(module: "ReAct", status: "completed")
      )
    end

    context "with async execution" do
      it "tracks job progress through all stages" do
        job = program.call_async(question: "Complex calculation question")
        
        expect(job.status).to eq("pending")
        wait_for_job(job.id)
        expect(job.reload.status).to eq("completed")
        expect(job.result).to be_present
      end
    end
  end
end
```

## Monitoring and Reporting

1. **Test Metrics**: Track test execution time, flakiness rate
2. **Coverage Reports**: Integration point coverage analysis
3. **Performance Benchmarks**: Track performance regressions
4. **Error Patterns**: Identify common failure modes

## Next Steps

1. Create `spec/integration/` directory structure
2. Implement test helpers and fixtures
3. Begin with Phase 1 core integration tests
4. Set up CI pipeline for integration tests
5. Document test patterns and best practices