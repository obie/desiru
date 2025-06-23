#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/desiru'

# Test script to debug MIPROv2 failures
puts "Testing MIPROv2 optimizer..."

# Set up basic requirements
signature = Desiru::Signature.new('question: string -> answer: string')
model = double('Model', call: { content: 'test response' })

# Create a test module class
test_module_class = Class.new(Desiru::Module) do
  attr_accessor :instruction

  def forward(inputs)
    { answer: "Answer to: #{inputs[:question]}" }
  end

  def with_demos(demos)
    new_instance = self.class.new(signature, model: model)
    new_instance.instance_variable_set(:@demos, demos)
    new_instance
  end
end

# Create a test program class
test_program_class = Class.new(Desiru::Program) do
  attr_reader :qa_module

  def initialize(qa_module: nil, **kwargs)
    super(**kwargs)
    @qa_module = qa_module
  end

  def forward(inputs)
    @qa_module.call(inputs)
  end

  def modules
    { qa: @qa_module }
  end

  def setup_modules
    # Override to prevent default setup
  end
end

# Try to create the optimizer
begin
  optimizer = Desiru::Optimizers::MIPROv2.new(metric: :exact_match)
  puts "✓ Created MIPROv2 optimizer"
rescue StandardError => e
  puts "✗ Failed to create optimizer: #{e.message}"
  puts e.backtrace.first(5)
  exit 1
end

# Test basic functionality
test_module = test_module_class.new(signature, model: model)
test_program = test_program_class.new(qa_module: test_module)

trainset = [
  Desiru::Core::Example.new(question: 'What is 2+2?', answer: '4'),
  Desiru::Core::Example.new(question: 'What is the capital of France?', answer: 'Paris')
]

begin
  optimizer.compile(test_program, trainset: trainset, valset: trainset)
  puts "✓ Compilation completed"
rescue StandardError => e
  puts "✗ Compilation failed: #{e.message}"
  puts e.backtrace.first(5)
end

puts "Done."
