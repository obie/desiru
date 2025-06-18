#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::RaixAdapter.new(
    provider: :openai,
    model: 'gpt-3.5-turbo',
    api_key: ENV['OPENAI_API_KEY'] || raise('Please set OPENAI_API_KEY environment variable')
  )
end

# Create a module with typed signature and descriptions
summarizer = Desiru::Modules::Predict.new(
  'document: string, max_length: int -> summary: string, key_points: list',
  descriptions: {
    'document' => 'The text document to summarize',
    'max_length' => 'Maximum number of words in the summary',
    'summary' => 'A concise summary of the document',
    'key_points' => 'List of key points from the document'
  }
)

# Test document
document = <<~TEXT
  Ruby is a dynamic, open source programming language with a focus on simplicity and productivity.
  It has an elegant syntax that is natural to read and easy to write. Ruby was created by Yukihiro
  Matsumoto in the mid-1990s. The language emphasizes the principle of least surprise, meaning that
  the language should behave in a way that minimizes confusion for experienced users.
TEXT

# Generate summary
result = summarizer.call(document: document, max_length: 50)

puts 'Original Document:'
puts document
puts "\nSummary (max #{result.to_h[:max_length] || 50} words):"
puts result.summary
puts "\nKey Points:"
result.key_points.each_with_index do |point, i|
  puts "#{i + 1}. #{point}"
end
