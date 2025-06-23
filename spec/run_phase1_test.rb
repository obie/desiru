#!/usr/bin/env ruby
# frozen_string_literal: true

# Simple test runner for phase1_integration_spec.rb
require 'rspec'
require_relative 'spec_helper'

# Run only one test to see the error
RSpec::Core::Runner.run(['integration/phase1_integration_spec.rb', '--format', 'documentation'])
