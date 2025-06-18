# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/autorun'
require 'minitest/reporters'
require 'desiru'

# Use a nice progress reporter
Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

# Test helper methods
module MinitestHelper
  # Setup method to be called in test setup
  def setup_desiru
    # Clear configuration before each test
    Desiru.configuration = Desiru::Configuration.new
  end

  # Create a simple test module
  def create_test_module(signature_str = 'input: string -> output: string')
    klass = Class.new(Desiru::Module) do
      define_method :forward do |**inputs|
        # Simple processing logic
        result = {}
        inputs.each do |k, v|
          result[k == :input ? :output : k] = "processed: #{v}"
        end
        result
      end
    end

    # Create instance with signature and a mock model
    mock_model = create_mock_model
    klass.new(signature_str, model: mock_model)
  end

  # Create a mock model for testing
  def create_mock_model
    model = Object.new
    def model.complete(_prompt)
      { text: 'mocked response' }
    end
    model
  end

  # Create a module that doesn't require LLM calls
  def create_deterministic_module(name = 'TestModule', description = 'Test module')
    Class.new(Desiru::Module) do
      signature name, description

      input 'input', type: 'string', desc: 'Input value'
      output 'output', type: 'string', desc: 'Output value'

      def forward(input:)
        { output: "processed: #{input}" }
      end
    end
  end

  # Mock LLM model for tests that need it
  def with_mock_model
    original_model = Desiru.configuration.default_model

    # Create a simple mock model
    mock_model = Object.new
    def mock_model.call(_prompt)
      { result: 'mocked response' }
    end

    Desiru.configuration.default_model = mock_model
    yield
  ensure
    Desiru.configuration.default_model = original_model
  end
end

# Include helper in all tests
class Minitest::Test
  include MinitestHelper

  # Automatically setup Desiru before each test
  def setup
    setup_desiru
    super if defined?(super)
  end
end
