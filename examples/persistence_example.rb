#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'desiru/persistence'

# Configure persistence
Desiru::Persistence.database_url = 'sqlite://desiru_example.db'

# Connect and migrate
puts "Setting up database..."
Desiru::Persistence.connect!
Desiru::Persistence.migrate!

# Access repositories
module_executions = Desiru::Persistence[:module_executions]
api_requests = Desiru::Persistence[:api_requests]
optimization_results = Desiru::Persistence[:optimization_results]
training_examples = Desiru::Persistence[:training_examples]

# Example 1: Track module executions
puts "\n1. Tracking module executions:"
execution = module_executions.create_for_module('TextSummarizer', { text: 'Long article...' })
puts "Created execution: #{execution.id}"

# Simulate processing
sleep 0.5
result = { summary: 'Article summary', word_count: 50 }
module_executions.complete(execution.id, result, { model: 'gpt-3.5-turbo' })
puts "Completed execution with result"

# Example 2: Store API requests
puts "\n2. Storing API requests:"
api_request = api_requests.create(
  method: 'POST',
  path: '/api/v1/summarize',
  remote_ip: '127.0.0.1',
  headers: { 'Content-Type' => 'application/json' },
  params: { text: 'Long article...' },
  status_code: 200,
  response_body: { summary: 'Article summary' },
  response_time: 0.234
)
puts "Stored API request: #{api_request.path} (#{api_request.duration_ms}ms)"

# Example 3: Track optimization results
puts "\n3. Recording optimization results:"
opt_result = optimization_results.create_result(
  module_name: 'TextSummarizer',
  optimizer_type: 'BootstrapFewShot',
  score: 0.89,
  baseline_score: 0.75,
  training_size: 50,
  parameters: { temperature: 0.7, max_tokens: 150 },
  metrics: { accuracy: 0.89, f1_score: 0.87 }
)
puts "Optimization improved performance by #{opt_result.improvement_percentage}%"

# Example 4: Store training examples
puts "\n4. Managing training examples:"
examples = [
  { inputs: { text: 'Example 1' }, outputs: { summary: 'Summary 1' } },
  { inputs: { text: 'Example 2' }, outputs: { summary: 'Summary 2' } },
  { inputs: { text: 'Example 3' }, outputs: { summary: 'Summary 3' } }
]

training_examples.bulk_create('TextSummarizer', examples)
puts "Created #{examples.length} training examples"

# Example 5: Query data
puts "\n5. Querying stored data:"
puts "- Module execution success rate: #{module_executions.success_rate}%"
puts "- Recent API requests: #{api_requests.recent(5).map(&:path).join(', ')}"
puts "- Best optimization score: #{optimization_results.find_best_for_module('TextSummarizer')&.score}"
puts "- Training examples available: #{training_examples.count}"

# Example 6: Analytics
puts "\n6. Analytics:"
puts "- Average response time: #{api_requests.average_response_time}s"
puts "- Requests per minute: #{api_requests.requests_per_minute(60)}"
puts "- Top API paths:"
api_requests.top_paths(3).each do |path_info|
  puts "  #{path_info[:path]}: #{path_info[:count]} requests"
end

# Example 7: Dataset splitting
puts "\n7. Dataset management:"
splits = training_examples.split_dataset('TextSummarizer')
puts "- Training set: #{splits[:training].length} examples"
puts "- Validation set: #{splits[:validation].length} examples"
puts "- Test set: #{splits[:test].length} examples"

# Export for training
puts "\n8. Export training data:"
export_data = training_examples.export_for_training('TextSummarizer', format: :dspy)
puts "Exported #{export_data.length} examples in DSPy format"

# Cleanup
puts "\nCleaning up..."
Desiru::Persistence.disconnect!
puts "Done!"
