#!/usr/bin/env ruby
# frozen_string_literal: true

# Test if we can load the integration test file without errors
$LOAD_PATH.unshift File.expand_path('../../lib', __dir__)

puts "Testing basic file loading..."

begin
  # Test loading minimal spec helper components
  require_relative '../lib/desiru/core/example'
  require_relative '../lib/desiru/core/prediction'
  require_relative '../lib/desiru/signature'
  require_relative '../lib/desiru/field'
  require_relative '../lib/desiru/errors'
  require_relative '../lib/desiru/core/trace'

  puts "✓ Core classes loaded successfully"

  # Test loading the actual test file to check for syntax errors
  require 'rspec'

  # Create a minimal test double for RSpec
  class MockModel
    def complete(_args)
      { content: "answer: test response" }
    end
  end

  # Define the double method that RSpec provides
  def double(_name, responses = {})
    obj = MockModel.new
    responses.each do |method, response|
      obj.define_singleton_method(method) { response }
    end
    obj
  end

  # Test that we can load the updated integration test file
  load File.expand_path('./integration/phase1_integration_spec.rb', __dir__)
  puts "✓ Phase 1 integration test file loads without syntax errors"
rescue StandardError => e
  puts "❌ Loading failed: #{e.message}"
  puts e.backtrace.first(3)
end

puts "Basic loading test complete!"
