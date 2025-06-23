#!/usr/bin/env ruby
# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

require 'desiru'

# Simple test runner to identify issues with Phase 1 integration tests
puts "=== Phase 1 Integration Test Issue Analysis ==="

puts "\n1. Testing Core classes exist..."

begin
  Desiru::Core::Example.new(question: "What is 2+2?", answer: "4")
  puts "✓ Desiru::Core::Example works"
rescue StandardError => e
  puts "❌ Desiru::Core::Example failed: #{e.message}"
end

begin
  Desiru::Core::Prediction.new(question: "What is 3+3?", answer: "6", confidence: 0.95)
  puts "✓ Desiru::Core::Prediction works"
rescue StandardError => e
  puts "❌ Desiru::Core::Prediction failed: #{e.message}"
end

begin
  Desiru::Core::TraceCollector.new
  puts "✓ Desiru::Core::TraceCollector works"
rescue StandardError => e
  puts "❌ Desiru::Core::TraceCollector failed: #{e.message}"
end

puts "\n2. Testing Module classes exist..."

begin
  # Check if Predict exists and how to instantiate it
  puts "Checking Desiru::Modules::Predict..."
  if defined?(Desiru::Modules::Predict)
    puts "✓ Desiru::Modules::Predict is defined"
    # Try to instantiate with proper signature
    signature = Desiru::Signature.new('question: string -> answer: string')
    model = double('model', complete: { content: 'test answer' })
    Desiru::Modules::Predict.new(signature, model: model)
    puts "✓ Desiru::Modules::Predict can be instantiated"
  else
    puts "❌ Desiru::Modules::Predict not defined"
  end
rescue StandardError => e
  puts "❌ Desiru::Modules::Predict failed: #{e.message}"
end

begin
  puts "Checking Desiru::Modules::ProgramOfThought..."
  if defined?(Desiru::Modules::ProgramOfThought)
    puts "✓ Desiru::Modules::ProgramOfThought is defined"
    signature = Desiru::Signature.new('question: string -> answer: string, code: string')
    model = double('model', complete: { content: 'test answer' })
    Desiru::Modules::ProgramOfThought.new(signature, model: model)
    puts "✓ Desiru::Modules::ProgramOfThought can be instantiated"
  else
    puts "❌ Desiru::Modules::ProgramOfThought not defined"
  end
rescue StandardError => e
  puts "❌ Desiru::Modules::ProgramOfThought failed: #{e.message}"
end

begin
  puts "Checking Desiru::Modules::MultiChainComparison..."
  if defined?(Desiru::Modules::MultiChainComparison)
    puts "✓ Desiru::Modules::MultiChainComparison is defined"
    signature = Desiru::Signature.new('question: string -> answer: string, reasoning: string')
    model = double('model', complete: { content: 'test answer' })
    Desiru::Modules::MultiChainComparison.new(signature, model: model, num_chains: 3)
    puts "✓ Desiru::Modules::MultiChainComparison can be instantiated"
  else
    puts "❌ Desiru::Modules::MultiChainComparison not defined"
  end
rescue StandardError => e
  puts "❌ Desiru::Modules::MultiChainComparison failed: #{e.message}"
end

begin
  puts "Checking Desiru::Modules::BestOfN..."
  if defined?(Desiru::Modules::BestOfN)
    puts "✓ Desiru::Modules::BestOfN is defined"
    signature = Desiru::Signature.new('question: string -> answer: string')
    model = double('model', complete: { content: 'test answer' })
    Desiru::Modules::BestOfN.new(signature, model: model, n_samples: 3)
    puts "✓ Desiru::Modules::BestOfN can be instantiated"
  else
    puts "❌ Desiru::Modules::BestOfN not defined"
  end
rescue StandardError => e
  puts "❌ Desiru::Modules::BestOfN failed: #{e.message}"
end

puts "\n3. Testing Optimizer classes..."

begin
  puts "Checking Desiru::Optimizers::MIPROv2..."
  if defined?(Desiru::Optimizers::MIPROv2)
    puts "✓ Desiru::Optimizers::MIPROv2 is defined"
    Desiru::Optimizers::MIPROv2.new(max_iterations: 2, num_candidates: 3)
    puts "✓ Desiru::Optimizers::MIPROv2 can be instantiated"
  else
    puts "❌ Desiru::Optimizers::MIPROv2 not defined"
  end
rescue StandardError => e
  puts "❌ Desiru::Optimizers::MIPROv2 failed: #{e.message}"
end

puts "\n4. Testing Compiler classes..."

begin
  puts "Checking Desiru::Core::Compiler..."
  if defined?(Desiru::Core::Compiler)
    puts "✓ Desiru::Core::Compiler is defined"
    Desiru::Core::Compiler.new
    puts "✓ Desiru::Core::Compiler can be instantiated"
  else
    puts "❌ Desiru::Core::Compiler not defined"
  end
rescue StandardError => e
  puts "❌ Desiru::Core::Compiler failed: #{e.message}"
end

puts "\n5. Testing Program classes..."

begin
  puts "Checking Desiru::Program..."
  if defined?(Desiru::Program)
    puts "✓ Desiru::Program is defined"
    Desiru::Program.new
    puts "✓ Desiru::Program can be instantiated"
  else
    puts "❌ Desiru::Program not defined"
  end
rescue StandardError => e
  puts "❌ Desiru::Program failed: #{e.message}"
end

puts "\n=== Analysis Complete ==="
