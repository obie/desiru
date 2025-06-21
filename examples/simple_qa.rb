#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'

# Configure Desiru with OpenAI model
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    model: 'gpt-3.5-turbo',
    api_key: ENV['OPENAI_API_KEY'] || raise('Please set OPENAI_API_KEY environment variable')
  )
end

# Create a simple question-answering module
qa = Desiru::Modules::Predict.new('question -> answer')

# Ask a question
result = qa.call(question: 'What is the capital of France?')
puts 'Question: What is the capital of France?'
puts "Answer: #{result.answer}"

# Create a Chain of Thought module for more complex reasoning
cot = Desiru::Modules::ChainOfThought.new('question -> answer')

# Ask a more complex question
result = cot.call(question: 'Two dice are tossed. What is the probability that the sum equals two?')
puts "\nQuestion: Two dice are tossed. What is the probability that the sum equals two?"
puts "Answer: #{result.answer}"
puts "Reasoning: #{result.reasoning}" if result.respond_to?(:reasoning)
