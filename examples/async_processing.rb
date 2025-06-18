#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'sidekiq'

# Example: Asynchronous Processing with Desiru
# This example demonstrates how to use background jobs for LLM operations

# Configure Desiru with a mock model for demonstration
Desiru.configure do |config|
  # In a real application, you would configure your actual model here
  # config.default_model = Desiru::Models::OpenAI.new(api_key: ENV['OPENAI_API_KEY'])

  # Redis URL for background job storage
  config.redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379'
end

# Mock model for demonstration
class MockModel
  def complete(_prompt, **_options)
    # Simulate processing time
    sleep(0.5)

    # Return mock response
    {
      content: "answer: This is a mock response for demonstration"
    }
  end

  def to_config
    { type: 'mock' }
  end
end

# Configure Desiru with mock model
Desiru.configuration.default_model = MockModel.new

puts "=== Desiru Async Processing Example ==="
puts

# Example 1: Single async prediction
puts "1. Single Async Prediction:"
qa_module = Desiru::Predict.new("question -> answer")

# Submit async job
result = qa_module.call_async(question: "What is the capital of France?")
puts "   Job ID: #{result.job_id}"
puts "   Status: Processing..."

# Check if ready (non-blocking)
sleep(0.1)
puts "   Ready? #{result.ready?}"

# Wait for result (blocking with timeout)
begin
  final_result = result.wait(timeout: 5)
  puts "   Result: #{final_result.answer}"
rescue Desiru::TimeoutError => e
  puts "   Error: #{e.message}"
end

puts

# Example 2: Batch processing
puts "2. Batch Processing:"
questions = [
  { question: "What is 2+2?" },
  { question: "What is the capital of Japan?" },
  { question: "Who wrote Romeo and Juliet?" }
]

batch_result = qa_module.call_batch_async(questions)
puts "   Batch ID: #{batch_result.job_id}"
puts "   Processing #{questions.size} questions..."

# Wait for batch to complete
batch_result.wait(timeout: 10)

# Get results
results = batch_result.results
stats = batch_result.stats

puts "   Stats:"
puts "     - Total: #{stats[:total]}"
puts "     - Successful: #{stats[:successful]}"
puts "     - Failed: #{stats[:failed]}"
puts "     - Success Rate: #{(stats[:success_rate] * 100).round(1)}%"

puts "   Results:"
results.each_with_index do |result, index|
  if result
    puts "     [#{index}] #{result.answer}"
  else
    puts "     [#{index}] Failed"
  end
end

puts

# Example 3: Error handling
puts "3. Error Handling:"

# Create a module that will fail
class FailingModel
  def complete(_prompt, **_options)
    raise StandardError, "Simulated model failure"
  end

  def to_config
    { type: 'failing' }
  end
end

failing_module = Desiru::Predict.new("question -> answer", model: FailingModel.new)
async_result = failing_module.call_async(question: "This will fail")

begin
  async_result.wait(timeout: 2)
rescue Desiru::ModuleError => e
  puts "   Caught error: #{e.message}"
  error_info = async_result.error
  puts "   Error class: #{error_info[:class]}"
  puts "   Error message: #{error_info[:message]}"
end

puts
puts "=== Example Complete ==="
puts
puts "Note: In a production environment, you would:"
puts "1. Have Sidekiq workers running: bundle exec sidekiq"
puts "2. Use real language models instead of mocks"
puts "3. Implement proper error handling and monitoring"
puts "4. Consider using Sidekiq Pro for additional features"
