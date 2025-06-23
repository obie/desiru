# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Trace Collection System Integration' do
  let(:mock_signature) do
    "text: string -> result: string"
  end

  let(:test_inputs) { { text: "Hello world" } }
  let(:test_outputs) { { result: "Processed: Hello world" } }

  before do
    Desiru::Core.reset_traces!
  end

  describe 'TraceCollector functionality' do
    let(:collector) { Desiru::Core::TraceCollector.new }

    it 'collects traces correctly' do
      trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: test_inputs,
        outputs: test_outputs
      )

      collector.collect(trace)

      expect(collector.size).to eq(1)
      expect(collector.traces.first).to eq(trace)
    end

    it 'supports filtering traces' do
      trace1 = Desiru::Core::Trace.new(
        module_name: 'Module1',
        signature: mock_signature,
        inputs: test_inputs,
        outputs: test_outputs
      )

      trace2 = Desiru::Core::Trace.new(
        module_name: 'Module2',
        signature: mock_signature,
        inputs: test_inputs,
        outputs: test_outputs
      )

      collector.add_filter { |trace| trace.module_name == 'Module1' }
      collector.collect(trace1)
      collector.collect(trace2)

      expect(collector.size).to eq(1)
      expect(collector.traces.first.module_name).to eq('Module1')
    end

    it 'handles multiple filters correctly' do
      collector.add_filter { |trace| trace.success? }
      collector.add_filter { |trace| trace.module_name.start_with?('Test') }

      success_trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: test_inputs,
        outputs: test_outputs,
        metadata: { success: true }
      )

      failed_trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: test_inputs,
        outputs: {},
        metadata: { success: false }
      )

      wrong_name_trace = Desiru::Core::Trace.new(
        module_name: 'OtherModule',
        signature: mock_signature,
        inputs: test_inputs,
        outputs: test_outputs,
        metadata: { success: true }
      )

      collector.collect(success_trace)
      collector.collect(failed_trace)
      collector.collect(wrong_name_trace)

      expect(collector.size).to eq(1)
      expect(collector.traces.first).to eq(success_trace)
    end

    it 'can be disabled and re-enabled' do
      trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: test_inputs,
        outputs: test_outputs
      )

      collector.disable
      collector.collect(trace)
      expect(collector.size).to eq(0)

      collector.enable
      collector.collect(trace)
      expect(collector.size).to eq(1)
    end

    it 'provides useful query methods' do
      traces = [
        Desiru::Core::Trace.new(
          module_name: 'Module1',
          signature: mock_signature,
          inputs: test_inputs,
          outputs: test_outputs,
          metadata: { success: true }
        ),
        Desiru::Core::Trace.new(
          module_name: 'Module2',
          signature: mock_signature,
          inputs: test_inputs,
          outputs: test_outputs,
          metadata: { success: false, error: 'Test error' }
        ),
        Desiru::Core::Trace.new(
          module_name: 'Module1',
          signature: mock_signature,
          inputs: test_inputs,
          outputs: test_outputs,
          metadata: { success: true }
        )
      ]

      traces.each { |trace| collector.collect(trace) }

      expect(collector.by_module('Module1').size).to eq(2)
      expect(collector.by_module('Module2').size).to eq(1)
      expect(collector.successful.size).to eq(2)
      expect(collector.failed.size).to eq(1)
      expect(collector.recent(2).size).to eq(2)
    end

    it 'exports traces correctly' do
      trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: test_inputs,
        outputs: test_outputs,
        metadata: { custom: 'value' }
      )

      collector.collect(trace)
      exported = collector.export

      expect(exported).to be_an(Array)
      expect(exported.size).to eq(1)
      expect(exported.first).to include(
        module_name: 'TestModule',
        inputs: test_inputs,
        outputs: test_outputs
      )
      expect(exported.first[:metadata]).to include(custom: 'value')
    end

    it 'converts traces to examples' do
      trace1 = Desiru::Core::Trace.new(
        module_name: 'Module1',
        signature: mock_signature,
        inputs: { question: 'What is 2+2?' },
        outputs: { answer: '4' }
      )

      trace2 = Desiru::Core::Trace.new(
        module_name: 'Module2',
        signature: mock_signature,
        inputs: { text: 'Hello' },
        outputs: { response: 'Hi there!' }
      )

      collector.collect(trace1)
      collector.collect(trace2)

      examples = collector.to_examples

      expect(examples.size).to eq(2)
      expect(examples.first).to be_a(Desiru::Core::Example)
      expect(examples.first[:question]).to eq('What is 2+2?')
      expect(examples.first[:answer]).to eq('4')
    end
  end

  describe 'TraceContext functionality' do
    let(:collector) { Desiru::Core::TraceCollector.new }
    let(:context) { Desiru::Core::TraceContext.new(collector) }

    it 'manages trace lifecycle correctly' do
      expect(collector.size).to eq(0)

      context.start_trace(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: test_inputs
      )

      # No trace collected yet (only started)
      expect(collector.size).to eq(0)

      trace = context.end_trace(outputs: test_outputs)

      expect(collector.size).to eq(1)
      expect(trace).to be_a(Desiru::Core::Trace)
      expect(trace.module_name).to eq('TestModule')
      expect(trace.inputs).to eq(test_inputs)
      expect(trace.outputs).to eq(test_outputs)
      expect(trace.duration).to be > 0
    end

    it 'handles errors during tracing' do
      context.start_trace(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: test_inputs
      )

      error = StandardError.new('Test error')
      trace = context.record_error(error)

      expect(collector.size).to eq(1)
      expect(trace).to be_a(Desiru::Core::Trace)
      expect(trace.error?).to be(true)
      expect(trace.success?).to be(false)
      expect(trace.metadata[:error]).to eq('Test error')
      expect(trace.metadata[:error_class]).to eq('StandardError')
    end

    it 'supports block-based tracing with automatic cleanup' do
      result = context.with_trace(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: test_inputs
      ) do
        sleep 0.001 # Simulate some work
        test_outputs
      end

      expect(result).to eq(test_outputs)
      expect(collector.size).to eq(1)

      trace = collector.traces.first
      expect(trace.module_name).to eq('TestModule')
      expect(trace.inputs).to eq(test_inputs)
      expect(trace.outputs).to eq(test_outputs)
      expect(trace.success?).to be(true)
      expect(trace.duration).to be > 0
    end

    it 'handles exceptions in block-based tracing' do
      expect do
        context.with_trace(
          module_name: 'TestModule',
          signature: mock_signature,
          inputs: test_inputs
        ) do
          raise StandardError, 'Block failed'
        end
      end.to raise_error(StandardError, 'Block failed')

      expect(collector.size).to eq(1)

      trace = collector.traces.first
      expect(trace.error?).to be(true)
      expect(trace.success?).to be(false)
      expect(trace.metadata[:error]).to eq('Block failed')
    end

    it 'handles nested tracing correctly' do
      context.with_trace(
        module_name: 'OuterModule',
        signature: mock_signature,
        inputs: { operation: 'outer' }
      ) do
        inner_result = context.with_trace(
          module_name: 'InnerModule',
          signature: mock_signature,
          inputs: { operation: 'inner' }
        ) do
          { inner_result: 'success' }
        end

        { outer_result: 'success', inner: inner_result }
      end

      expect(collector.size).to eq(2)

      # Inner trace should be collected first
      inner_trace = collector.traces.first
      outer_trace = collector.traces.last

      expect(inner_trace.module_name).to eq('InnerModule')
      expect(outer_trace.module_name).to eq('OuterModule')
      expect(outer_trace.outputs[:inner][:inner_result]).to eq('success')
    end
  end

  describe 'Global trace collection' do
    it 'provides global trace collector access' do
      global_collector = Desiru::Core.trace_collector

      expect(global_collector).to be_a(Desiru::Core::TraceCollector)
      expect(Desiru::Core.trace_collector).to be(global_collector) # Same instance
    end

    it 'provides global trace context access' do
      global_context = Desiru::Core.trace_context

      expect(global_context).to be_a(Desiru::Core::TraceContext)
      expect(global_context.collector).to be(Desiru::Core.trace_collector)
    end

    it 'supports resetting global trace state' do
      # Collect some traces
      Desiru::Core.trace_collector.collect(
        Desiru::Core::Trace.new(
          module_name: 'TestModule',
          signature: mock_signature,
          inputs: test_inputs,
          outputs: test_outputs
        )
      )

      expect(Desiru::Core.trace_collector.size).to eq(1)

      # Reset and verify clean state
      Desiru::Core.reset_traces!

      expect(Desiru::Core.trace_collector.size).to eq(0)
      expect(Desiru::Core.trace_context.collector).to be(Desiru::Core.trace_collector)
    end

    it 'maintains trace integrity across resets' do
      # Create some traces
      old_collector = Desiru::Core.trace_collector
      old_collector.collect(
        Desiru::Core::Trace.new(
          module_name: 'TestModule',
          signature: mock_signature,
          inputs: test_inputs,
          outputs: test_outputs
        )
      )

      # Reset
      Desiru::Core.reset_traces!
      new_collector = Desiru::Core.trace_collector

      # Should be different instances
      expect(new_collector).not_to be(old_collector)
      expect(new_collector.size).to eq(0)
      expect(old_collector.size).to eq(1) # Old collector unchanged
    end
  end

  describe 'Performance and memory characteristics' do
    let(:collector) { Desiru::Core::TraceCollector.new }

    it 'handles large numbers of traces efficiently' do
      start_time = Time.now

      1000.times do |i|
        trace = Desiru::Core::Trace.new(
          module_name: "Module#{i % 10}",
          signature: mock_signature,
          inputs: { index: i },
          outputs: { result: "result_#{i}" },
          metadata: { iteration: i }
        )
        collector.collect(trace)
      end

      end_time = Time.now

      expect(collector.size).to eq(1000)
      expect(end_time - start_time).to be < 1.0 # Should complete in under 1 second

      # Test query performance
      query_start = Time.now
      module_traces = collector.by_module('Module5')
      successful_traces = collector.successful
      query_end = Time.now

      expect(module_traces.size).to eq(100)
      expect(successful_traces.size).to eq(1000) # All should be successful
      expect(query_end - query_start).to be < 0.1 # Fast queries
    end

    it 'manages memory efficiently for large traces' do
      large_data = Array.new(1000) { |i| { id: i, data: "item_#{i}" } }

      10.times do |i|
        trace = Desiru::Core::Trace.new(
          module_name: "LargeModule#{i}",
          signature: mock_signature,
          inputs: { large_input: large_data },
          outputs: { processed_data: large_data.reverse },
          metadata: { size: large_data.size }
        )
        collector.collect(trace)
      end

      expect(collector.size).to eq(10)
      expect(collector.traces.first.inputs[:large_input].size).to eq(1000)

      # Verify data integrity
      first_trace = collector.traces.first
      expect(first_trace.inputs[:large_input].first[:id]).to eq(0)
      expect(first_trace.outputs[:processed_data].first[:id]).to eq(999)
    end
  end

  describe 'Integration with real module execution' do
    let(:test_module_class) do
      Class.new do
        attr_reader :signature, :trace_enabled

        def initialize
          @signature = "text: string -> result: string"
          @trace_enabled = false
        end

        def enable_trace!
          @trace_enabled = true
        end

        def disable_trace!
          @trace_enabled = false
        end

        def forward(**inputs)
          if @trace_enabled
            Desiru::Core.trace_context.with_trace(
              module_name: self.class.name,
              signature: @signature,
              inputs: inputs
            ) do
              process_inputs(inputs)
            end
          else
            process_inputs(inputs)
          end
        end

        private

        def process_inputs(inputs)
          { result: "Processed: #{inputs[:text]}" }
        end
      end
    end

    it 'integrates seamlessly with traced module execution' do
      test_module = test_module_class.new

      # Execute without tracing
      result1 = test_module.forward(text: "Hello")
      expect(Desiru::Core.trace_collector.size).to eq(0)
      expect(result1[:result]).to eq("Processed: Hello")

      # Enable tracing and execute
      test_module.enable_trace!
      result2 = test_module.forward(text: "World")

      expect(Desiru::Core.trace_collector.size).to eq(1)
      expect(result2[:result]).to eq("Processed: World")

      trace = Desiru::Core.trace_collector.traces.first
      expect(trace.module_name).to eq(test_module.class.name)
      expect(trace.inputs[:text]).to eq("World")
      expect(trace.outputs[:result]).to eq("Processed: World")
      expect(trace.success?).to be(true)
    end

    it 'captures errors during traced execution' do
      error_module_class = Class.new(test_module_class) do
        private

        def process_inputs(inputs)
          raise StandardError, "Processing failed for: #{inputs[:text]}"
        end
      end

      error_module = error_module_class.new
      error_module.enable_trace!

      expect do
        error_module.forward(text: "ErrorTest")
      end.to raise_error(StandardError, "Processing failed for: ErrorTest")

      expect(Desiru::Core.trace_collector.size).to eq(1)

      trace = Desiru::Core.trace_collector.traces.first
      expect(trace.error?).to be(true)
      expect(trace.success?).to be(false)
      expect(trace.metadata[:error]).to eq("Processing failed for: ErrorTest")
    end
  end
end
