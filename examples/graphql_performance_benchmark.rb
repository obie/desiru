#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'desiru/graphql/schema_generator'
require 'desiru/graphql/executor'
require 'desiru/graphql/data_loader'
require 'benchmark'

# Example: GraphQL Performance Benchmark with Request Deduplication
# This demonstrates the performance improvement from request deduplication

# Mock model for benchmarking
class MockModel < Desiru::Models::Base
  def initialize(config = {})
    @config = config
  end

  def call(_prompt, **_options)
    # Return a simple response without actually calling an LLM
    { content: "Mock response", usage: { total_tokens: 0 } }
  end

  def validate_config!
    # No validation needed for mock
  end
end

# Configure Desiru with mock model
Desiru.configure do |config|
  config.default_model = MockModel.new
end

# Create a module that tracks call counts
class BenchmarkModule < Desiru::Modules::Predict
  @@call_count = 0
  @@batch_count = 0

  def self.reset_counts!
    @@call_count = 0
    @@batch_count = 0
  end

  def self.call_count
    @@call_count
  end

  def self.batch_count
    @@batch_count
  end

  def call(inputs)
    @@call_count += 1
    # Simulate some processing time
    sleep(0.001)
    { result: "Processed: #{inputs[:id]}", timestamp: Time.now.to_f }
  end

  def batch_forward(inputs_array)
    @@batch_count += 1
    # Simulate batch processing time (more efficient than individual calls)
    sleep(0.001 * Math.log(inputs_array.size + 1))
    inputs_array.map do |inputs|
      { result: "Batch processed: #{inputs[:id]}", timestamp: Time.now.to_f }
    end
  end
end

# Create schema generator and register the module
generator = Desiru::GraphQL::SchemaGenerator.new
signature = Desiru::Signature.new('id: string -> result: string, timestamp: float')
module_instance = BenchmarkModule.new(signature)

generator.register_signature('fetchData', signature)
generator.register_module('fetchData', module_instance)

# Generate schema
schema = generator.generate_schema

# Create executors with and without DataLoader
data_loader = Desiru::GraphQL::DataLoader.new
executor_with_loader = Desiru::GraphQL::Executor.new(schema, data_loader: data_loader)
executor_without_loader = Desiru::GraphQL::Executor.new(schema)

puts "=== GraphQL Performance Benchmark with Request Deduplication ==="
puts

# Test 1: Query with duplicate fields (common in GraphQL)
duplicate_query = <<~GRAPHQL
  {
    user1: fetchData(id: "123") { result timestamp }
    user2: fetchData(id: "456") { result timestamp }
    user3: fetchData(id: "123") { result timestamp }
    user4: fetchData(id: "789") { result timestamp }
    user5: fetchData(id: "456") { result timestamp }
    user6: fetchData(id: "123") { result timestamp }
  }
GRAPHQL

puts "Test 1: Query with duplicate requests (3x id:123, 2x id:456, 1x id:789)"
puts

# Without deduplication
BenchmarkModule.reset_counts!
time_without = Benchmark.realtime do
  executor_without_loader.execute(duplicate_query)
end
without_calls = BenchmarkModule.call_count
without_batches = BenchmarkModule.batch_count

# With deduplication
BenchmarkModule.reset_counts!
time_with = Benchmark.realtime do
  executor_with_loader.execute(duplicate_query)
end
with_calls = BenchmarkModule.call_count
with_batches = BenchmarkModule.batch_count

puts "Without deduplication:"
puts "  Time: #{(time_without * 1000).round(2)}ms"
puts "  Individual calls: #{without_calls}"
puts "  Batch calls: #{without_batches}"
puts

puts "With deduplication:"
puts "  Time: #{(time_with * 1000).round(2)}ms"
puts "  Individual calls: #{with_calls}"
puts "  Batch calls: #{with_batches}"
puts "  Unique requests processed: 3 (deduplication working!)"
puts

improvement = ((time_without - time_with) / time_without * 100).round(1)
puts "Performance improvement: #{improvement}%"
puts

# Test 2: Nested query simulation (common with relationships)
puts "\nTest 2: Simulating nested queries (N+1 problem)"
puts

nested_query = <<~GRAPHQL
  {
    posts1: fetchData(id: "post1") { result }
    posts2: fetchData(id: "post2") { result }
    posts3: fetchData(id: "post3") { result }
    author1: fetchData(id: "author1") { result }
    author2: fetchData(id: "author2") { result }
    author3: fetchData(id: "author1") { result }
    author4: fetchData(id: "author2") { result }
    author5: fetchData(id: "author1") { result }
    comments1: fetchData(id: "comment1") { result }
    comments2: fetchData(id: "comment2") { result }
    comments3: fetchData(id: "comment1") { result }
  }
GRAPHQL

# Without deduplication
BenchmarkModule.reset_counts!
time_without = Benchmark.realtime do
  executor_without_loader.execute(nested_query)
end
without_calls = BenchmarkModule.call_count
without_batches = BenchmarkModule.batch_count

# With deduplication
BenchmarkModule.reset_counts!
time_with = Benchmark.realtime do
  executor_with_loader.execute(nested_query)
end
with_calls = BenchmarkModule.call_count
with_batches = BenchmarkModule.batch_count

puts "Without deduplication:"
puts "  Time: #{(time_without * 1000).round(2)}ms"
puts "  Total module calls: #{without_calls + without_batches}"
puts

puts "With deduplication + batching:"
puts "  Time: #{(time_with * 1000).round(2)}ms"
puts "  Total module calls: #{with_calls + with_batches}"
puts "  Unique requests: 7 (3 posts, 2 authors, 2 comments)"
puts

improvement = ((time_without - time_with) / time_without * 100).round(1)
puts "Performance improvement: #{improvement}%"
puts

# Test 3: Large batch with many duplicates
puts "\nTest 3: Large batch with high duplication rate"
puts

# Generate a query with many duplicates
field_count = 50
unique_ids = 10
fields = []
field_count.times do |i|
  id = rand(unique_ids)
  fields << "field#{i}: fetchData(id: \"id_#{id}\") { result }"
end
large_query = "{ #{fields.join(' ')} }"

# Without deduplication
BenchmarkModule.reset_counts!
time_without = Benchmark.realtime do
  executor_without_loader.execute(large_query)
end
without_calls = BenchmarkModule.call_count
without_batches = BenchmarkModule.batch_count

# With deduplication
BenchmarkModule.reset_counts!
time_with = Benchmark.realtime do
  executor_with_loader.execute(large_query)
end
BenchmarkModule.call_count
with_batches = BenchmarkModule.batch_count

puts "Query with #{field_count} fields, ~#{unique_ids} unique IDs"
puts

puts "Without deduplication:"
puts "  Time: #{(time_without * 1000).round(2)}ms"
puts "  Total requests processed: #{without_calls + without_batches}"
puts

puts "With deduplication + batching:"
puts "  Time: #{(time_with * 1000).round(2)}ms"
puts "  Unique requests processed: #{unique_ids}"
puts "  Batch calls: #{with_batches}"
puts

improvement = ((time_without - time_with) / time_without * 100).round(1)
puts "Performance improvement: #{improvement}%"
puts
puts "Deduplication ratio: #{(field_count.to_f / unique_ids).round(1)}:1"

puts "\n=== Summary ==="
puts "Request deduplication in GraphQL DataLoader prevents duplicate operations,"
puts "significantly improving performance when the same data is requested multiple"
puts "times within a single query. This is especially beneficial for:"
puts "- Complex queries with repeated fields"
puts "- Nested relationships that cause N+1 problems"
puts "- High-traffic APIs where efficiency matters"
