#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'

# Mock model for demonstration
class MockModel
  def complete(_messages:, **_options)
    # Simple mock that returns predefined responses
    { choices: [{ message: { content: "Mock response" } }] }
  end
end

# Configure Desiru with assertions
Desiru.configure do |config|
  config.default_model = MockModel.new
  config.logger = Logger.new($stdout).tap do |log|
    log.level = Logger::INFO
    log.formatter = proc do |severity, datetime, _, msg|
      "[#{severity}] #{datetime}: #{msg}\n"
    end
  end
end

# Configure assertion behavior
Desiru::Assertions.configure do |config|
  config.max_assertion_retries = 2
  config.assertion_retry_delay = 0.5
end

# Example 1: Module with confidence assertion
class FactChecker < Desiru::Module
  def forward(statement:)
    # Simulate fact checking with confidence score
    facts = [
      { statement: "The sky is blue", confidence: 0.95 },
      { statement: "Water boils at 100°C", confidence: 0.98 },
      { statement: "Cats can fly", confidence: 0.1 },
      { statement: "The Earth is flat", confidence: 0.05 }
    ]

    # Find confidence for the statement
    fact = facts.find { |f| f[:statement].downcase == statement.downcase }
    confidence = fact ? fact[:confidence] : rand(0.3..0.9)

    result = {
      statement: statement,
      confidence: confidence,
      verified: confidence > 0.7
    }

    # Assert high confidence for fact verification
    Desiru.assert(
      result[:confidence] > 0.7,
      "Low confidence score: #{result[:confidence]}. Cannot verify statement."
    )

    result
  end
end

# Example 2: Module with suggestions for best practices
class CodeReviewer < Desiru::Module
  def forward(code:, language:)
    review = {
      code: code,
      language: language,
      issues: [],
      suggestions: []
    }

    # Simulate code analysis
    if code.include?('TODO')
      review[:issues] << "Found TODO comment"
      review[:suggestions] << "Consider creating a ticket for TODO items"
    end

    if language == 'ruby' && !code.include?('frozen_string_literal')
      review[:suggestions] << "Add frozen_string_literal pragma"
    end

    # Suggest having tests
    Desiru.suggest(
      code.include?('test') || code.include?('spec'),
      "No tests found in the code. Consider adding test coverage."
    )

    # Suggest documentation
    Desiru.suggest(
      code.include?('#') || code.include?('/**'),
      "No comments found. Consider adding documentation."
    )

    review[:score] = 100 - (review[:issues].length * 10)
    review
  end
end

# Example 3: Module combining assertions and suggestions
class DataValidator < Desiru::Module
  def forward(data:, schema:)
    validation = {
      data: data,
      valid: true,
      errors: [],
      warnings: []
    }

    # Required field assertion
    schema[:required]&.each do |field|
      if !data.key?(field) || data[field].nil?
        validation[:valid] = false
        validation[:errors] << "Missing required field: #{field}"
      end
    end

    # Assert data is valid
    Desiru.assert(
      validation[:valid],
      "Data validation failed: #{validation[:errors].join(', ')}"
    )

    # Suggest best practices
    if data.is_a?(Hash)
      Desiru.suggest(
        data.keys.all? { |k| k.is_a?(Symbol) },
        "Consider using symbols for hash keys for better performance"
      )
    end

    # Check data types (suggestions)
    schema[:types]&.each do |field, expected_type|
      next unless data.key?(field)

      actual_type = data[field].class
      Desiru.suggest(
        actual_type == expected_type,
        "Field '#{field}' is #{actual_type}, expected #{expected_type}"
      )
    end

    validation
  end
end

# Demonstrate the modules
puts "=== Assertion Examples ==="
puts

# Example 1: Fact Checker with passing assertion
puts "1. Fact Checker - Valid Statement:"
fact_checker = FactChecker.new('statement:str -> statement:str, confidence:float, verified:bool')
begin
  result = fact_checker.call(statement: "Water boils at 100°C")
  puts "  ✓ Statement: #{result[:statement]}"
  puts "  ✓ Confidence: #{result[:confidence]}"
  puts "  ✓ Verified: #{result[:verified]}"
rescue Desiru::Assertions::AssertionError => e
  puts "  ✗ Assertion failed: #{e.message}"
end
puts

# Example 2: Fact Checker with failing assertion
puts "2. Fact Checker - False Statement:"
begin
  result = fact_checker.call(statement: "Cats can fly")
  puts "  ✓ Statement verified with confidence: #{result[:confidence]}"
rescue Desiru::Assertions::AssertionError => e
  puts "  ✗ Assertion failed after retries: #{e.message}"
  puts "  ✗ Module: #{e.module_name}"
  puts "  ✗ Retries: #{e.retry_count}"
end
puts

# Example 3: Code Reviewer with suggestions
puts "3. Code Reviewer - With Suggestions:"
code_reviewer = CodeReviewer.new(
  'code:str, language:str -> code:str, language:str, issues:list, suggestions:list, score:int'
)
code = <<~RUBY
  def calculate_sum(numbers)
    # TODO: Add validation
    numbers.sum
  end
RUBY

result = code_reviewer.call(code: code, language: 'ruby')
puts "  Code review score: #{result[:score]}"
puts "  Issues: #{result[:issues].join(', ')}"
puts "  Suggestions: #{result[:suggestions].join(', ')}"
puts

# Example 4: Data Validator with mixed validations
puts "4. Data Validator - Complete Example:"
validator = DataValidator.new('data:dict, schema:dict -> data:dict, valid:bool, errors:list, warnings:list')

schema = {
  required: %i[name email],
  types: {
    name: String,
    email: String,
    age: Integer
  }
}

# Valid data
puts "  a) Valid data:"
begin
  valid_data = { name: "John Doe", email: "john@example.com", age: 30 }
  result = validator.call(data: valid_data, schema: schema)
  puts "    ✓ Validation passed"
  puts "    ✓ Data is valid: #{result[:valid]}"
rescue Desiru::Assertions::AssertionError => e
  puts "    ✗ Validation failed: #{e.message}"
end

# Invalid data
puts "  b) Invalid data (missing required field):"
begin
  invalid_data = { name: "Jane Doe", age: "twenty-five" }
  validator.call(data: invalid_data, schema: schema)
  puts "    ✓ Validation passed"
rescue Desiru::Assertions::AssertionError => e
  puts "    ✗ Validation failed: #{e.message}"
end

puts
puts "=== Assertion Configuration ==="
puts "Max assertion retries: #{Desiru::Assertions.configuration.max_assertion_retries}"
puts "Retry delay: #{Desiru::Assertions.configuration.assertion_retry_delay}s"
puts "Assertions logged: #{Desiru::Assertions.configuration.log_assertions}"
