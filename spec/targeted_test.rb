#!/usr/bin/env ruby
# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

# Load specific files we need to test
require_relative '../lib/desiru/core/example'
require_relative '../lib/desiru/core/prediction'
require_relative '../lib/desiru/signature'
require_relative '../lib/desiru/field'
require_relative '../lib/desiru/errors'

puts "=== Targeted Class Testing ==="

puts "\n1. Testing Core classes..."

begin
  example = Desiru::Core::Example.new(question: "What is 2+2?", answer: "4")
  puts "✓ Desiru::Core::Example: #{example.question}"
rescue StandardError => e
  puts "❌ Desiru::Core::Example failed: #{e.message}"
end

begin
  prediction = Desiru::Core::Prediction.new(question: "What is 3+3?", answer: "6", confidence: 0.95)
  puts "✓ Desiru::Core::Prediction: #{prediction.answer}"
rescue StandardError => e
  puts "❌ Desiru::Core::Prediction failed: #{e.message}"
end

begin
  signature = Desiru::Signature.new('question: string -> answer: string')
  puts "✓ Signature: #{signature.raw_signature}"
rescue StandardError => e
  puts "❌ Signature failed: #{e.message}"
end

puts "\nNow checking what issues the Phase 1 tests will have..."

# Check specific issues from the test file
puts "\n2. Checking Phase 1 test specific issues..."

# Issue 1: Prediction.from_example method
begin
  example = Desiru::Core::Example.new(question: "What is 2+2?", answer: "4")
  if Desiru::Core::Prediction.respond_to?(:from_example)
    Desiru::Core::Prediction.from_example(example)
    puts "✓ Prediction.from_example works"
  else
    puts "❌ Prediction.from_example method doesn't exist"
  end
rescue StandardError => e
  puts "❌ Prediction.from_example failed: #{e.message}"
end

puts "\n=== Issues Identified ==="
puts "1. Need to implement Prediction.from_example class method"
puts "2. Need to check if other modules can be instantiated without model dependency"
puts "3. Need to check TraceContext.with_collector method"
puts "4. Need to check compilation interface changes"
