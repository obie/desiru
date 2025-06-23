#!/usr/bin/env ruby
# frozen_string_literal: true

# Test specific Phase 1 fixes
require 'bundler/setup'
require 'rspec'

# Add lib to load path
$LOAD_PATH.unshift(File.join(File.dirname(__FILE__), '..', 'lib'))

require 'desiru'

# Create a simple mock model class for testing
class SimpleMockModel
  def initialize(responses = {})
    @responses = responses
    @call_count = 0
  end

  def complete(prompt, **options)
    @call_count += 1
    if @responses.is_a?(Proc)
      @responses.call(prompt, options)
    elsif @responses.is_a?(Hash) && prompt.is_a?(Hash)
      # Look for specific patterns in the prompt
      user_content = prompt[:user] || ""
      response = @responses.find { |pattern, _| user_content.include?(pattern) }&.[](1)
      response || { content: "answer: default response" }
    else
      @responses.is_a?(Hash) ? @responses[:default] || { content: "answer: default" } : @responses
    end
  end

  attr_reader :call_count
end

RSpec.describe "Phase 1 Integration Test Fixes" do
  describe "Trace Collection Test Fix" do
    it "handles mock model interface correctly" do
      mock_model = SimpleMockModel.new({ content: "answer: Paris" })
      signature = Desiru::Signature.new('question: string -> answer: string')

      collector = Desiru::Core::TraceCollector.new

      Desiru::Core::TraceContext.with_collector(collector) do
        module_instance = Desiru::Modules::Predict.new(signature, model: mock_model)
        result = module_instance.call(question: "What is the capital of France?")

        expect(result).to be_a(Desiru::ModuleResult)
        expect(result.answer).to eq("Paris")
      end

      traces = collector.traces
      expect(traces).not_to be_empty
      expect(traces.first.module_name).to include("Predict")
      expect(traces.first.inputs[:question]).to eq("What is the capital of France?")
    end
  end

  describe "Forward vs Process Method Fix" do
    it "uses forward method instead of process" do
      signature = Desiru::Signature.new('question: string -> answer: string')
      mock_model = SimpleMockModel.new({ content: "answer: test" })

      faulty_module = Class.new(Desiru::Module) do
        def forward(_inputs)
          raise "Intentional error"
        end
      end.new(signature, model: mock_model)

      bon = Desiru::Modules::BestOfN.new(signature, model: mock_model, base_module: faulty_module, n_samples: 3)

      # Should handle errors gracefully
      expect { bon.call(question: "test") }.not_to raise_error
    end
  end

  describe "ProgramOfThought Integration" do
    it "generates and executes code with proper mock response" do
      responses = proc do |_prompt, _options|
        { content: "answer: 60\ncode: result = 15 * 4; { answer: result.to_s }" }
      end

      mock_model = SimpleMockModel.new(responses)
      pot_signature = Desiru::Signature.new('question: string -> answer: string, code: string')
      pot_module = Desiru::Modules::ProgramOfThought.new(pot_signature, model: mock_model)

      result = pot_module.call(question: "Calculate the sum of integers from 1 to 10")

      expect(result.code).not_to be_nil
      expect(result.answer).not_to be_nil
    end
  end
end

# Run the tests
exit_code = RSpec::Core::Runner.run([])
exit exit_code
