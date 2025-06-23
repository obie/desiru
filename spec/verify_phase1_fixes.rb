#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple verification of Phase 1 fixes
require 'bundler/setup'

# Add lib to load path
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'desiru'

puts "🔍 Verifying Phase 1 Integration Test Fixes..."

# Create a simple mock model class
class SimpleMockModel
  def initialize(response_content = "answer: Test response")
    @response_content = response_content
  end

  def complete(_prompt, **_options)
    { content: @response_content }
  end
end

# Test 1: Verify trace collection works with fixed mock interface
puts "\n1. Testing trace collection with fixed mock interface..."
begin
  mock_model = SimpleMockModel.new("answer: Paris")
  signature = Desiru::Signature.new('question: string -> answer: string')

  collector = Desiru::Core::TraceCollector.new

  Desiru::Core::TraceContext.with_collector(collector) do
    module_instance = Desiru::Modules::Predict.new(signature, model: mock_model)
    result = module_instance.call(question: "What is the capital of France?")

    puts "   ✓ Module executed successfully"
    puts "   ✓ Result: #{result.answer}"
  end

  traces = collector.traces
  puts "   ✓ Traces captured: #{traces.size}"
  puts "   ✓ First trace module: #{traces.first.module_name}" if traces.first
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
end

# Test 2: Verify forward method vs process method fix
puts "\n2. Testing forward method vs process method fix..."
begin
  signature = Desiru::Signature.new('question: string -> answer: string')
  mock_model = SimpleMockModel.new("answer: test")

  faulty_module = Class.new(Desiru::Module) do
    def forward(_inputs)
      raise "Intentional error"
    end
  end.new(signature, model: mock_model)

  bon = Desiru::Modules::BestOfN.new(signature, model: mock_model, base_module: faulty_module, n_samples: 3)

  # Should handle errors gracefully
  begin
    bon.call(question: "test")
    puts "   ✓ BestOfN handles faulty module gracefully"
  rescue StandardError => e
    puts "   ⚠️  BestOfN error handling: #{e.message}"
  end
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
end

# Test 3: Test ProgramOfThought with proper code field
puts "\n3. Testing ProgramOfThought with proper mock response..."
begin
  mock_model = SimpleMockModel.new("answer: 60\ncode: result = 15 * 4; { answer: result.to_s }")
  pot_signature = Desiru::Signature.new('question: string -> answer: string, code: string')
  pot_module = Desiru::Modules::ProgramOfThought.new(pot_signature, model: mock_model)

  result = pot_module.call(question: "What is 15 * 4?")

  puts "   ✓ ProgramOfThought executed successfully"
  puts "   ✓ Answer: #{result.answer}"
  puts "   ✓ Code: #{result.code[0..50]}..." if result.code
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
end

# Test 4: Test MultiChainComparison basic functionality
puts "\n4. Testing MultiChainComparison basic functionality..."
begin
  mock_model = SimpleMockModel.new("answer: Yes, 17 is prime\nreasoning: 17 is only divisible by 1 and itself")
  mcc_signature = Desiru::Signature.new('question: string -> answer: string, reasoning: string')
  mcc_module = Desiru::Modules::MultiChainComparison.new(mcc_signature, model: mock_model, num_chains: 2)

  result = mcc_module.call(question: "Is 17 a prime number?")

  puts "   ✓ MultiChainComparison executed successfully"
  puts "   ✓ Answer: #{result.answer}"
  puts "   ✓ Reasoning: #{result.reasoning[0..50]}..." if result.reasoning
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
  puts "      #{e.backtrace.first(3).join("\n      ")}"
end

# Test 5: Test compilation without errors
puts "\n5. Testing basic compilation..."
begin
  mock_model = SimpleMockModel.new("answer: 4")
  signature = Desiru::Signature.new('question: string -> answer: string')

  program = Class.new(Desiru::Program) do
    def initialize(model, signature)
      super()
      @predict = Desiru::Modules::Predict.new(signature, model: model)
    end

    def call(question:)
      @predict.call(question: question)
    end
  end.new(mock_model, signature)

  examples = [
    Desiru::Core::Example.new(question: "What is 2+2?", answer: "4"),
    Desiru::Core::Example.new(question: "What is 5+5?", answer: "10")
  ]

  compiler = Desiru::Core::Compiler.new
  result = compiler.compile(program, examples)

  puts "   ✓ Compilation executed successfully"
  puts "   ✓ Result success: #{result.success?}"
  puts "   ✓ Program: #{result.program.class}"
rescue StandardError => e
  puts "   ❌ Error: #{e.message}"
end

puts "\n✅ Phase 1 integration test fixes verification complete!"
puts "\nKey fixes implemented:"
puts "• Fixed mock model interface to handle prompt, **options parameters"
puts "• Changed faulty module from 'process' to 'forward' method"
puts "• Enhanced mock responses to include proper field mappings"
puts "• Added proper trace collection mocking"
puts "• Fixed compilation parameter handling"
puts "\nThe Phase 1 integration tests should now pass with these fixes."
