#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    model: 'gpt-3.5-turbo',
    api_key: ENV['OPENAI_API_KEY'] || raise('Please set OPENAI_API_KEY environment variable')
  )
end

# Create a sentiment classifier
classifier = Desiru::Modules::ChainOfThought.new(
  'text -> sentiment: string, confidence: float'
)

# Training examples
training_examples = [
  {
    text: 'This product is amazing! I love it so much.',
    sentiment: 'positive',
    confidence: 0.95
  },
  {
    text: 'Terrible experience. Would not recommend.',
    sentiment: 'negative',
    confidence: 0.90
  },
  {
    text: "It's okay, nothing special but does the job.",
    sentiment: 'neutral',
    confidence: 0.80
  }
]

# Optimize the classifier with few-shot examples
optimizer = Desiru::Optimizers::BootstrapFewShot.new(
  metric: :exact_match,
  max_bootstrapped_demos: 3
)

puts "Optimizing classifier with #{training_examples.size} examples..."
optimized_classifier = optimizer.compile(classifier, trainset: training_examples)

# Test on new examples
test_texts = [
  'This framework is absolutely fantastic!',
  "I'm disappointed with the quality.",
  'The service is adequate for basic needs.'
]

puts "\n#{'=' * 50}"
puts 'Sentiment Analysis Results:'
puts '=' * 50

test_texts.each do |text|
  result = optimized_classifier.call(text: text)
  puts "\nText: \"#{text}\""
  puts "Sentiment: #{result.sentiment}"
  puts "Confidence: #{(result.confidence * 100).round(1)}%"
  puts "Reasoning: #{result.reasoning}" if result.respond_to?(:reasoning)
end
