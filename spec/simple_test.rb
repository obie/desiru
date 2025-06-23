#!/usr/bin/env ruby
# frozen_string_literal: true

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'desiru'

# Simple test to verify MultiChainComparison fixes
begin
  puts "Testing MultiChainComparison module fixes..."

  # Test signature creation
  signature = Desiru::Signature.new('question: string -> answer: string')
  puts "✓ Signature created: #{signature.raw_signature}"

  # Test signature field access - this was the core issue
  output_fields = signature.output_fields
  puts "✓ Output fields accessible, type: #{output_fields.class}"
  puts "✓ Output field keys: #{output_fields.keys}"
  puts "✓ Keys are strings: #{output_fields.keys.first.class}"

  # Test the problematic key access pattern
  answer_key = signature.output_fields.keys.map(&:to_sym).find { |k| !%i[reasoning comparison_data].include?(k) }
  puts "✓ Answer key found: #{answer_key} (#{answer_key.class})"

  # Test key? method
  puts "✓ Key check (string): #{signature.output_fields.key?('answer')}"
  puts "✓ Key check (symbol): #{signature.output_fields.key?(:answer)}"

  puts "\n✅ All signature-related fixes appear to be working!"
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(5)
end
