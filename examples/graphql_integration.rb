#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'desiru/graphql/schema_generator'

# Example: GraphQL Integration with Desiru
# This demonstrates how to generate GraphQL schemas from Desiru signatures

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    model: 'gpt-3.5-turbo',
    api_key: ENV['OPENAI_API_KEY'] || raise('Please set OPENAI_API_KEY environment variable')
  )
end

# Create a schema generator
generator = Desiru::GraphQL::SchemaGenerator.new

# Register multiple Desiru signatures as GraphQL operations
generator.register_signature(
  'translateText',
  Desiru::Signature.new(
    'text: string, target_language: string, source_language?: string -> translation: string, confidence: float'
  )
)

generator.register_signature(
  'analyzeSentiment',
  Desiru::Signature.new(
    "text: string -> sentiment: Literal['positive', 'negative', 'neutral'], score: float"
  )
)

generator.register_signature(
  'summarizeBatch',
  Desiru::Signature.new(
    'documents: list[string], max_length: int -> summaries: list[string], total_words: int'
  )
)

# Generate the GraphQL schema
schema = generator.generate_schema

# Example GraphQL query execution
puts "GraphQL Schema generated with operations:"
schema.query.fields.each do |name, field|
  puts "  - #{name}: #{field.description}"
end

# Example queries you can run:
puts "\nExample GraphQL queries:"
puts <<~GRAPHQL
  # Translation query
  query {
    translateText(text: "Hello world", targetLanguage: "es") {
      translation
      confidence
    }
  }

  # Sentiment analysis query#{'  '}
  query {
    analyzeSentiment(text: "This framework is amazing!") {
      sentiment
      score
    }
  }

  # Batch summarization query
  query {
    summarizeBatch(
      documents: ["Long document 1...", "Long document 2..."],
      maxLength: 100
    ) {
      summaries
      totalWords
    }
  }
GRAPHQL

# Execute a sample query
result = schema.execute(<<~GRAPHQL)
  query {
    analyzeSentiment(text: "GraphQL integration with Desiru is fantastic!") {
      sentiment
      score
    }
  }
GRAPHQL

puts "\nQuery result:"
puts result.to_h.inspect

# Integration with GraphQL servers
puts "\n\nTo use this schema with a GraphQL server (e.g., graphql-ruby with Rails):"
puts <<~RUBY
  # In your GraphQL controller:
  class GraphQLController < ApplicationController
    def execute
      result = DesiruSchema.execute(
        params[:query],
        variables: params[:variables],
        context: { current_user: current_user }
      )
      render json: result
    end
  end

  # Where DesiruSchema is your generated schema
  DesiruSchema = generator.generate_schema
RUBY
