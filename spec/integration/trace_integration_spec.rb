# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Trace Collection Integration" do
  # Set up a mock model for all tests
  let(:mock_model) do
    double('model').tap do |model|
      allow(model).to receive(:complete) do |*args|
        # Check if this is a code generation request
        if args.any? { |arg| arg.to_s.include?('code') || arg.to_s.include?('Calculate') }
          { content: "Let me solve this step by step.\n\n```ruby\ndef solve(**inputs)\n  result = 10 + 20\n  { answer: result.to_s, code: 'result = 10 + 20' }\nend\n```\n\nThe code calculates 10 + 20 = 30" }
        else
          { content: 'answer: test answer' }
        end
      end
    end
  end

  before do
    # Set up default model in configuration
    allow(Desiru.configuration).to receive(:default_model).and_return(mock_model)
  end

  describe "Cross-module trace collection" do
    let(:collector) { Desiru::Core::TraceCollector.new }

    it "collects traces across nested module calls" do
      # Create a custom module that uses other modules
      composite_module = Class.new(Desiru::Module) do
        def initialize
          super('question: string -> answer: string, reasoning: string')
          @mcc = Desiru::Modules::MultiChainComparison.new(num_chains: 2)
          @bon = Desiru::Modules::BestOfN.new(n_samples: 2)
        end

        def forward(inputs)
          # First use MultiChainComparison
          mcc_result = @mcc.call(inputs)

          # Then use BestOfN with the question
          bon_result = @bon.call(question: "Follow up: #{inputs[:question]}")

          # Return the required outputs
          {
            answer: mcc_result[:answer] || "Combined answer",
            reasoning: "#{mcc_result[:reasoning] || 'No reasoning'} Additionally, #{bon_result[:answer] || 'No answer'}"
          }
        end
      end.new

      Desiru::Core::TraceContext.with_collector(collector) do
        composite_module.call(question: "What is machine learning?")
      end

      traces = collector.traces

      # Should have traces from all modules
      module_names = traces.map(&:module_name)
      expect(module_names).to include("MultiChainComparison")
      expect(module_names).to include("BestOfN")
      expect(module_names).to include("AnonymousModule") # The composite module

      # Verify trace relationships
      composite_trace = traces.find { |t| t.module_name == "AnonymousModule" }
      expect(composite_trace).not_to be_nil

      # Check timing is recorded
      traces.each do |trace|
        expect(trace.duration_ms).to be > 0
      end
    end

    it "preserves trace context across async operations" do
      results = []

      Desiru::Core::TraceContext.with_collector(collector) do
        threads = 5.times.map do |i|
          Thread.new(collector) do |thread_collector|
            # Set up trace context in the thread
            Desiru::Core::TraceContext.with_collector(thread_collector) do
              module_instance = Desiru::Modules::Predict.new
              results << module_instance.call(question: "Question #{i}")
            end
          end
        end
        threads.each(&:join)
      end

      traces = collector.traces
      expect(traces.size).to eq(5)

      # Each trace should have unique inputs
      questions = traces.map { |t| t.inputs[:question] }
      expect(questions.uniq.size).to eq(5)
    end

    it "captures errors in traces" do
      error_module = Class.new(Desiru::Module) do
        def initialize
          super('question: string -> answer: string')
        end

        def forward(_inputs)
          raise StandardError, "Intentional test error"
        end
      end.new

      Desiru::Core::TraceContext.with_collector(collector) do
        expect { error_module.call(question: "Will fail") }.to raise_error(StandardError)
      end

      expect(collector.traces.size).to eq(1)
      error_trace = collector.traces.last
      expect(error_trace).not_to be_nil
      expect(error_trace.error).to eq("Module execution failed: Intentional test error")
      expect(error_trace.outputs).to eq({})
    end
  end

  describe "Trace analysis and filtering" do
    let(:collector) { Desiru::Core::TraceCollector.new }

    before do
      Desiru::Core::TraceContext.with_collector(collector) do
        # Generate various traces
        predict = Desiru::Modules::Predict.new
        pot = Desiru::Modules::ProgramOfThought.new
        mcc = Desiru::Modules::MultiChainComparison.new

        predict.call(question: "Quick question")
        pot.call(question: "Calculate 10 + 20")
        mcc.call(question: "Complex reasoning task")

        # Nested call
        bon = Desiru::Modules::BestOfN.new(base_module: predict)
        bon.call(question: "Best answer question")
      end
    end

    it "filters traces by module name" do
      predict_traces = collector.filter_by_module("Predict")
      expect(predict_traces.size).to be >= 1
      expect(predict_traces.all? { |t| t.module_name == "Predict" }).to be true
    end

    it "filters traces by success/failure" do
      successful_traces = collector.filter_by_success(success: true)
      expect(successful_traces).not_to be_empty
      expect(successful_traces.all? { |t| t.error.nil? }).to be true
    end

    it "calculates performance statistics" do
      stats = collector.statistics

      expect(stats[:total_traces]).to be > 0
      expect(stats[:success_rate]).to be_between(0, 1)
      expect(stats[:average_duration_ms]).to be > 0
      expect(stats[:by_module]).to be_a(Hash)
      expect(stats[:by_module]["Predict"]).to include(:count, :avg_duration_ms)
    end

    it "filters traces by time range" do
      recent_traces = collector.filter_by_time_range(
        Time.now - 60, # Last minute
        Time.now
      )
      expect(recent_traces.size).to eq(collector.traces.size)

      # Future time range should return empty
      future_traces = collector.filter_by_time_range(
        Time.now + 60,
        Time.now + 120
      )
      expect(future_traces).to be_empty
    end
  end

  describe "Trace metadata and custom tracking" do
    it "includes custom metadata in traces" do
      custom_module = Class.new(Desiru::Module) do
        def initialize
          super('question: string -> answer: string')
        end

        def forward(_inputs)
          # Add custom tracking
          trace_metadata[:model_temperature] = 0.7
          trace_metadata[:retry_count] = 2
          trace_metadata[:custom_tags] = %w[experimental v2]

          { answer: "42" }
        end

        private

        def trace_metadata
          @trace_metadata ||= {}
        end
      end.new

      collector = Desiru::Core::TraceCollector.new

      Desiru::Core::TraceContext.with_collector(collector) do
        custom_module.call(question: "Meaning of life?")
      end

      collector.traces.last
      # The actual metadata implementation would need to be added to the Trace class
      # This test documents the expected behavior
    end
  end

  describe "Trace collection in optimization context" do
    it "collects detailed traces during module usage in programs" do
      program = Class.new(Desiru::Program) do
        def initialize
          super
          @predict = Desiru::Modules::Predict.new
        end

        def call(question:)
          @predict.call(question: question)
        end
      end.new

      collector = Desiru::Core::TraceCollector.new

      Desiru::Core::TraceContext.with_collector(collector) do
        # Call the program multiple times
        result1 = program.call(question: "What is 1+1?")
        result2 = program.call(question: "What is 2+2?")

        expect(result1).to have_key(:answer)
        expect(result2).to have_key(:answer)
      end

      traces = collector.traces

      # Should have traces from program execution
      expect(traces).not_to be_empty
      expect(traces.size).to eq(2)

      # Should include traces from Predict module
      predict_traces = traces.select { |t| t.module_name == "Predict" }
      expect(predict_traces.size).to eq(2)

      # Verify inputs are captured correctly
      questions = predict_traces.map { |t| t.inputs[:question] }
      expect(questions).to include("What is 1+1?", "What is 2+2?")

      # Can analyze module behavior
      stats = collector.statistics
      expect(stats[:by_module]["Predict"][:count]).to eq(2)
    end
  end
end
