#!/usr/bin/env ruby
# frozen_string_literal: true

# Minimal test to verify core functionality
require 'bundler/setup'
require 'rspec'
require 'rspec/mocks'

# Add lib to load path
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

# Include RSpec mocks
include RSpec::Mocks::ExampleMethods

begin
  require 'desiru'
  puts "✓ Desiru loaded successfully"

  # Test basic classes
  signature = Desiru::Signature.new('question: string -> answer: string')
  puts "✓ Signature created: #{signature.input_fields.keys} -> #{signature.output_fields.keys}"

  example = Desiru::Core::Example.new(question: "What is 2+2?", answer: "4")
  puts "✓ Example created: #{example.question} -> #{example.answer}"

  prediction = Desiru::Core::Prediction.new(question: "What is 3+3?", answer: "6", confidence: 0.95)
  puts "✓ Prediction created: #{prediction.question} -> #{prediction.answer} (confidence: #{prediction.confidence})"

  # Test from_example method
  pred_from_example = Desiru::Core::Prediction.from_example(example)
  puts "✓ Prediction.from_example works: #{pred_from_example.question}"

  # Create a simple mock model class
  class SimpleMockModel
    def complete(_prompt, **_options)
      { content: "answer: Test response" }
    end
  end

  mock_model = SimpleMockModel.new

  # Test predict module
  predict_module = Desiru::Modules::Predict.new(signature, model: mock_model)
  puts "✓ Predict module created"

  result = predict_module.call(question: "What is the capital of France?")
  puts "✓ Predict module executed: #{result}"

  puts "\n✅ All basic tests passed!"
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  exit 1
end
