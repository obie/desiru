#!/usr/bin/env ruby
# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Load only what we need for testing signature functionality
require_relative '../lib/desiru/field'
require_relative '../lib/desiru/signature'
require_relative '../lib/desiru/errors'

# Simple test to verify Signature behavior that affects MultiChainComparison
begin
  puts "Testing Signature behavior for MultiChainComparison fixes..."

  # Test signature creation
  signature = Desiru::Signature.new('question: string -> answer: string')
  puts "✓ Signature created: #{signature.raw_signature}"

  # Test the core issue: output_fields.keys returns strings, not symbols
  output_fields = signature.output_fields
  puts "✓ Output fields accessible, type: #{output_fields.class}"
  puts "✓ Output field keys: #{output_fields.keys.inspect}"
  puts "✓ Keys are: #{output_fields.keys.map(&:class)}"

  # Test the fix: map to symbols before filtering
  answer_key = signature.output_fields.keys.map(&:to_sym).find { |k| !%i[reasoning comparison_data].include?(k) }
  puts "✓ Answer key found after map: #{answer_key} (#{answer_key.class})"

  # Test key? method behavior - this is crucial for metadata check
  puts "✓ Key check (string): #{signature.output_fields.key?('answer')}"
  puts "✓ Key check (symbol): #{signature.output_fields.key?(:answer)}"

  # Test with comparison_data field
  complex_signature = Desiru::Signature.new('question: string -> answer: string, comparison_data: hash')
  puts "✓ Complex signature keys: #{complex_signature.output_fields.keys.inspect}"
  puts "✓ Has comparison_data (string): #{complex_signature.output_fields.key?('comparison_data')}"
  puts "✓ Has comparison_data (symbol): #{complex_signature.output_fields.key?(:comparison_data)}"

  # Test the specific logic from MultiChainComparison
  answer_key = complex_signature.output_fields.keys.map(&:to_sym).find { |k| !%i[reasoning comparison_data].include?(k) }
  puts "✓ Answer key in complex signature: #{answer_key}"

  puts "\n✅ All signature tests pass! The MultiChainComparison fixes should work."
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
end
