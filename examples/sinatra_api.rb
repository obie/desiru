#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'rack'
require 'rack/handler/webrick'

# This example demonstrates how to create a lightweight REST API using Desiru's Sinatra integration

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY'] || 'your-api-key',
    model: 'gpt-3.5-turbo'
  )
end

# Define a simple text processing module
class TextProcessor < Desiru::Module
  signature 'TextProcessor', 'Process and analyze text'

  input 'text', type: 'string', desc: 'Text to process'
  input 'operation', type: 'string', desc: 'Operation to perform (uppercase, lowercase, reverse, analyze)'

  output 'result', type: 'string', desc: 'Processed text result'
  output 'metadata', type: 'dict', desc: 'Additional metadata about the operation'

  def forward(text:, operation:)
    result = case operation.downcase
             when 'uppercase'
               text.upcase
             when 'lowercase'
               text.downcase
             when 'reverse'
               text.reverse
             when 'analyze'
               "Text has #{text.length} characters and #{text.split.length} words"
             else
               raise ArgumentError, "Unknown operation: #{operation}"
             end

    {
      result: result,
      metadata: {
        original_length: text.length,
        processed_at: Time.now.iso8601,
        operation: operation
      }
    }
  end
end

# Define a calculator module
class Calculator < Desiru::Module
  signature 'Calculator', 'Perform basic math operations'

  input 'num1', type: 'float', desc: 'First number'
  input 'num2', type: 'float', desc: 'Second number'
  input 'operation', type: 'string', desc: 'Operation (+, -, *, /)'

  output 'result', type: 'float', desc: 'Calculation result'

  def forward(num1:, num2:, operation:)
    result = case operation
             when '+' then num1 + num2
             when '-' then num1 - num2
             when '*' then num1 * num2
             when '/'
               raise ArgumentError, "Division by zero" if num2.zero?

               num1 / num2
             else
               raise ArgumentError, "Unknown operation: #{operation}"
             end

    { result: result }
  end
end

# Create Sinatra API integration
api = Desiru::API.sinatra(async_enabled: true) do
  register_module '/text', TextProcessor.new,
                  description: 'Process text with various operations'

  register_module '/calculate', Calculator.new,
                  description: 'Perform basic math calculations'
end

# Create a Rack app with the API
app = api.to_rack_app

puts "Starting Sinatra-based Desiru API server on http://localhost:9293"
puts "\nAvailable endpoints:"
puts "  POST /api/v1/health - Health check"
puts "  POST /api/v1/text - Text processing"
puts "  POST /api/v1/calculate - Calculator"
puts "  POST /api/v1/async/text - Async text processing"
puts "  POST /api/v1/async/calculate - Async calculator"
puts "  GET  /api/v1/jobs/:job_id - Check async job status"
puts "\nExample requests:"
puts "  curl -X POST http://localhost:9293/api/v1/text " \
     "-H 'Content-Type: application/json' -d '{\"text\": \"Hello World\", \"operation\": \"uppercase\"}'"
puts "  curl -X POST http://localhost:9293/api/v1/calculate " \
     "-H 'Content-Type: application/json' -d '{\"num1\": 10, \"num2\": 5, \"operation\": \"+\"}'"
puts "\nPress Ctrl+C to stop the server"

# Start the server
Rack::Handler::WEBrick.run app, Port: 9293
