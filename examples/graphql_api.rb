#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'desiru/graphql/schema_generator'
require 'desiru/graphql/executor'

# Configure Desiru
Desiru.configure do |config|
  # Use OpenAI model for demonstration
  config.default_model = Desiru::Models::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY'] || raise('Please set OPENAI_API_KEY environment variable')
  )
end

# Create some example modules
class AnswerQuestion < Desiru::Module
  def initialize
    signature = Desiru::Signature.new(
      "question: string -> answer: string, confidence: float",
      descriptions: {
        question: "The question to answer",
        answer: "The answer to the question",
        confidence: "Confidence score between 0 and 1"
      }
    )
    super(signature)
  end

  def forward(question:)
    # Simulate processing
    {
      answer: "The answer to '#{question}' is 42.",
      confidence: 0.95
    }
  end
end

class SummarizeText < Desiru::Module
  def initialize
    signature = Desiru::Signature.new(
      "text: string, max_words: int -> summary: string, word_count: int",
      descriptions: {
        text: "The text to summarize",
        max_words: "Maximum words in summary",
        summary: "The summarized text",
        word_count: "Actual word count of summary"
      }
    )
    super(signature)
  end

  def forward(text:, max_words:)
    words = text.split.take(max_words)
    summary = words.join(' ') + (words.length < text.split.length ? '...' : '')

    {
      summary: summary,
      word_count: words.length
    }
  end
end

class ClassifySentiment < Desiru::Module
  def initialize
    signature = Desiru::Signature.new(
      "text: string -> sentiment: Literal['positive', 'negative', 'neutral'], reasoning: string"
    )
    super(signature)
  end

  def forward(text:)
    # Simple rule-based sentiment for demo
    positive_words = %w[good great excellent amazing wonderful]
    negative_words = %w[bad terrible awful horrible poor]

    text_lower = text.downcase
    positive_count = positive_words.count { |word| text_lower.include?(word) }
    negative_count = negative_words.count { |word| text_lower.include?(word) }

    if positive_count > negative_count
      sentiment = 'positive'
      reasoning = "Found #{positive_count} positive indicators"
    elsif negative_count > positive_count
      sentiment = 'negative'
      reasoning = "Found #{negative_count} negative indicators"
    else
      sentiment = 'neutral'
      reasoning = "No strong sentiment indicators found"
    end

    { sentiment: sentiment, reasoning: reasoning }
  end
end

# Set up GraphQL schema
puts "Setting up GraphQL schema..."
generator = Desiru::GraphQL::SchemaGenerator.new

# Register modules
generator.register_module(:answerQuestion, AnswerQuestion.new)
generator.register_module(:summarizeText, SummarizeText.new)
generator.register_module(:classifySentiment, ClassifySentiment.new)

# Generate schema
schema = generator.generate_schema

# Create executor with batch loading
executor = Desiru::GraphQL::Executor.new(schema, data_loader: generator.data_loader)

# Example queries
puts "\n=== Example 1: Simple Question ==="
query1 = <<~GRAPHQL
  query {
    answerQuestion(question: "What is the meaning of life?") {
      answer
      confidence
    }
  }
GRAPHQL

result1 = executor.execute(query1)
puts "Query: #{query1}"
puts "Result: #{result1.to_h}"

puts "\n=== Example 2: Text Summarization ==="
query2 = <<~GRAPHQL
  query {
    summarizeText(
      text: "Ruby is a dynamic, open source programming language with a focus on simplicity and productivity. It has an elegant syntax that is natural to read and easy to write."
      maxWords: 10
    ) {
      summary
      wordCount
    }
  }
GRAPHQL

result2 = executor.execute(query2)
puts "Query: #{query2}"
puts "Result: #{result2.to_h}"

puts "\n=== Example 3: Sentiment Classification ==="
query3 = <<~GRAPHQL
  query {
    classifySentiment(text: "This framework is absolutely amazing and wonderful!") {
      sentiment
      reasoning
    }
  }
GRAPHQL

result3 = executor.execute(query3)
puts "Query: #{query3}"
puts "Result: #{result3.to_h}"

puts "\n=== Example 4: Batch Query ==="
batch_query = <<~GRAPHQL
  query {
    positive: classifySentiment(text: "I love this great product") {
      sentiment
      reasoning
    }
    negative: classifySentiment(text: "This is terrible and awful") {
      sentiment
      reasoning
    }
    neutral: classifySentiment(text: "It exists and works") {
      sentiment
      reasoning
    }
  }
GRAPHQL

result4 = executor.execute(batch_query)
puts "Query: #{batch_query}"
puts "Result: #{result4.to_h}"

# Demonstrate batch execution of multiple queries
puts "\n=== Example 5: Batch Execution ==="
queries = [
  { query: 'query { answerQuestion(question: "What is Ruby?") { answer } }' },
  { query: 'query { answerQuestion(question: "What is GraphQL?") { answer } }' },
  { query: 'query { answerQuestion(question: "What is Desiru?") { answer } }' }
]

results = executor.execute_batch(queries)
puts "Executing #{queries.length} queries in batch..."
results.each_with_index do |result, i|
  puts "Query #{i + 1}: #{result.to_h}"
end
