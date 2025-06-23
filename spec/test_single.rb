#!/usr/bin/env ruby
# frozen_string_literal: true

# Quick test to see if basic loading works
begin
  require 'bundler/setup'
  require 'rspec'

  puts "Loading spec_helper..."
  load File.join(File.dirname(__FILE__), 'spec_helper.rb')

  puts "Loading phase1 test..."
  load File.join(File.dirname(__FILE__), 'integration', 'phase1_integration_spec.rb')

  puts "Running first test only..."
  RSpec.configure do |config|
    config.filter_run_including focus: true
    config.run_all_when_everything_filtered = true
  end

  # Mark the first test as focused
  RSpec.describe "Phase 1 Integration Tests" do
    describe "Core Infrastructure Integration" do
      it "integrates Example and Prediction classes", focus: true do
        example = Desiru::Core::Example.new(question: "What is 2+2?", answer: "4")
        prediction = Desiru::Core::Prediction.new(question: "What is 3+3?", answer: "6", confidence: 0.95)

        expect(example.question).to eq("What is 2+2?")
        expect(prediction.answer).to eq("6")
        expect(prediction.confidence).to eq(0.95)

        # Test conversion
        pred_from_example = Desiru::Core::Prediction.from_example(example)
        expect(pred_from_example.question).to eq(example.question)
      end
    end
  end

  RSpec::Core::Runner.run([])
rescue StandardError => e
  puts "Error: #{e.message}"
  puts e.backtrace.first(5).join("\n")
end
