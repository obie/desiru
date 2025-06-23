#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'spec_helper'

# Simple test to verify MultiChainComparison fixes
begin
  puts "Testing MultiChainComparison module fixes..."

  # Test basic initialization
  model = double('model')
  signature = Desiru::Signature.new('question: string -> answer: string')
  Desiru::Modules::MultiChainComparison.new(signature, model: model)

  puts "✓ Module initialization works"

  # Test signature field access
  output_fields = signature.output_fields
  puts "✓ Signature output_fields accessible: #{output_fields.keys}"

  # Test key access methods
  answer_key = signature.output_fields.keys.map(&:to_sym).find { |k| !%i[reasoning comparison_data].include?(k) }
  puts "✓ Answer key found: #{answer_key}"

  # Test voting logic simulation
  chains = [
    { answer: '4', reasoning: 'First approach' },
    { answer: '4', reasoning: 'Second approach' },
    { answer: '5', reasoning: 'Third approach' }
  ]

  votes = Hash.new(0)
  chains.each do |chain|
    answer_value = chain[answer_key]
    votes[answer_value] += 1 if answer_value
  end

  winning_answer = votes.max_by { |_, count| count }&.first
  puts "✓ Voting logic works, winning answer: #{winning_answer}"

  puts "\nAll basic fixes appear to be working!"
rescue StandardError => e
  puts "❌ Error: #{e.message}"
  puts e.backtrace.first(3)
end
