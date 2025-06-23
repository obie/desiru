# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Core::Trace do
  let(:signature) { Desiru::Signature.new('question -> answer') }
  let(:inputs) { { question: 'What is 2+2?' } }
  let(:outputs) { { answer: '4' } }
  let(:metadata) { { model: 'gpt-4', duration: 0.5 } }

  describe '#initialize' do
    it 'creates a trace with required parameters' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature,
        inputs: inputs,
        outputs: outputs,
        metadata: metadata
      )

      expect(trace.module_name).to eq('TestModule')
      expect(trace.signature).to eq(signature)
      expect(trace.inputs).to eq(inputs)
      expect(trace.outputs).to eq(outputs)
      expect(trace.metadata).to eq(metadata)
      expect(trace.timestamp).to be_a(Time)
    end
  end

  describe '#to_h' do
    it 'returns a hash representation' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature,
        inputs: inputs,
        outputs: outputs,
        metadata: metadata
      )

      hash = trace.to_h
      expect(hash[:module_name]).to eq('TestModule')
      expect(hash[:signature]).to eq(signature.to_h)
      expect(hash[:inputs]).to eq(inputs)
      expect(hash[:outputs]).to eq(outputs)
      expect(hash[:metadata]).to eq(metadata)
      expect(hash[:timestamp]).to be_a(Time)
    end
  end

  describe '#to_example' do
    it 'creates an Example from inputs and outputs' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature,
        inputs: inputs,
        outputs: outputs
      )

      example = trace.to_example
      expect(example).to be_a(Desiru::Core::Example)
      expect(example[:question]).to eq('What is 2+2?')
      expect(example[:answer]).to eq('4')
    end
  end

  describe '#success?' do
    it 'returns true when success is not false' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature,
        metadata: { success: true }
      )
      expect(trace.success?).to be true
    end

    it 'returns false when success is false' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature,
        metadata: { success: false }
      )
      expect(trace.success?).to be false
    end

    it 'returns true when success is not specified' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature
      )
      expect(trace.success?).to be true
    end
  end

  describe '#error?' do
    it 'returns true when error key exists' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature,
        metadata: { error: 'Something went wrong' }
      )
      expect(trace.error?).to be true
    end

    it 'returns false when error key does not exist' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature
      )
      expect(trace.error?).to be false
    end
  end

  describe '#duration' do
    it 'returns duration from metadata' do
      trace = described_class.new(
        module_name: 'TestModule',
        signature: signature,
        metadata: { duration: 1.5 }
      )
      expect(trace.duration).to eq(1.5)
    end
  end
end

RSpec.describe Desiru::Core::TraceCollector do
  let(:signature) { Desiru::Signature.new('input -> output') }
  let(:trace) do
    Desiru::Core::Trace.new(
      module_name: 'TestModule',
      signature: signature,
      inputs: { input: 'test' },
      outputs: { output: 'result' }
    )
  end

  describe '#collect' do
    it 'collects traces when enabled' do
      collector = described_class.new
      collector.collect(trace)

      expect(collector.traces).to include(trace)
      expect(collector.size).to eq(1)
    end

    it 'does not collect when disabled' do
      collector = described_class.new
      collector.disable
      collector.collect(trace)

      expect(collector.empty?).to be true
    end

    it 'applies filters to traces' do
      collector = described_class.new
      collector.add_filter { |t| t.module_name == 'AllowedModule' }

      collector.collect(trace)
      expect(collector.empty?).to be true

      allowed_trace = Desiru::Core::Trace.new(
        module_name: 'AllowedModule',
        signature: signature
      )
      collector.collect(allowed_trace)
      expect(collector.size).to eq(1)
    end
  end

  describe '#enable and #disable' do
    it 'controls trace collection' do
      collector = described_class.new
      expect(collector.enabled?).to be true

      collector.disable
      expect(collector.enabled?).to be false

      collector.enable
      expect(collector.enabled?).to be true
    end
  end

  describe '#recent' do
    it 'returns the most recent traces' do
      collector = described_class.new

      5.times do |i|
        trace = Desiru::Core::Trace.new(
          module_name: "Module#{i}",
          signature: signature
        )
        collector.collect(trace)
      end

      recent = collector.recent(3)
      expect(recent.size).to eq(3)
      expect(recent.last.module_name).to eq('Module4')
    end
  end

  describe '#by_module' do
    it 'filters traces by module name' do
      collector = described_class.new

      trace1 = Desiru::Core::Trace.new(module_name: 'ModuleA', signature: signature)
      trace2 = Desiru::Core::Trace.new(module_name: 'ModuleB', signature: signature)
      trace3 = Desiru::Core::Trace.new(module_name: 'ModuleA', signature: signature)

      collector.collect(trace1)
      collector.collect(trace2)
      collector.collect(trace3)

      module_a_traces = collector.by_module('ModuleA')
      expect(module_a_traces.size).to eq(2)
      expect(module_a_traces).to contain_exactly(trace1, trace3)
    end
  end

  describe '#successful and #failed' do
    it 'separates successful and failed traces' do
      collector = described_class.new

      success_trace = Desiru::Core::Trace.new(
        module_name: 'Module',
        signature: signature,
        metadata: { success: true }
      )

      failed_trace = Desiru::Core::Trace.new(
        module_name: 'Module',
        signature: signature,
        metadata: { success: false }
      )

      collector.collect(success_trace)
      collector.collect(failed_trace)

      expect(collector.successful).to contain_exactly(success_trace)
      expect(collector.failed).to contain_exactly(failed_trace)
    end
  end

  describe '#to_examples' do
    it 'converts traces to examples' do
      collector = described_class.new
      collector.collect(trace)

      examples = collector.to_examples
      expect(examples.size).to eq(1)
      expect(examples.first).to be_a(Desiru::Core::Example)
      expect(examples.first[:input]).to eq('test')
      expect(examples.first[:output]).to eq('result')
    end
  end

  describe '#export' do
    it 'exports traces as hashes' do
      collector = described_class.new
      collector.collect(trace)

      export = collector.export
      expect(export).to be_an(Array)
      expect(export.first).to be_a(Hash)
      expect(export.first[:module_name]).to eq('TestModule')
    end
  end
end

RSpec.describe Desiru::Core::TraceContext do
  let(:signature) { Desiru::Signature.new('input -> output') }
  let(:collector) { Desiru::Core::TraceCollector.new }
  let(:context) { described_class.new(collector) }

  describe '#start_trace and #end_trace' do
    it 'creates a trace from start to end' do
      context.start_trace(
        module_name: 'TestModule',
        signature: signature,
        inputs: { input: 'test' }
      )

      sleep 0.01 # Ensure some duration

      trace = context.end_trace(
        outputs: { output: 'result' },
        metadata: { model: 'gpt-4' }
      )

      expect(trace).to be_a(Desiru::Core::Trace)
      expect(trace.module_name).to eq('TestModule')
      expect(trace.inputs).to eq({ input: 'test' })
      expect(trace.outputs).to eq({ output: 'result' })
      expect(trace.metadata[:duration]).to be > 0
      expect(trace.metadata[:success]).to be true
      expect(trace.metadata[:model]).to eq('gpt-4')

      expect(collector.size).to eq(1)
    end
  end

  describe '#record_error' do
    it 'records an error trace' do
      context.start_trace(
        module_name: 'TestModule',
        signature: signature,
        inputs: { input: 'test' }
      )

      error = StandardError.new('Something went wrong')
      trace = context.record_error(error, outputs: { partial: 'data' })

      expect(trace.metadata[:success]).to be false
      expect(trace.metadata[:error]).to eq('Something went wrong')
      expect(trace.metadata[:error_class]).to eq('StandardError')
      expect(trace.outputs).to eq({ partial: 'data' })

      expect(collector.size).to eq(1)
    end
  end

  describe '#with_trace' do
    it 'wraps execution with tracing' do
      result = context.with_trace(
        module_name: 'TestModule',
        signature: signature,
        inputs: { input: 'test' }
      ) do
        { output: 'result' }
      end

      expect(result).to eq({ output: 'result' })
      expect(collector.size).to eq(1)

      trace = collector.traces.first
      expect(trace.outputs).to eq({ output: 'result' })
      expect(trace.success?).to be true
    end

    it 'captures errors and re-raises' do
      expect do
        context.with_trace(
          module_name: 'TestModule',
          signature: signature,
          inputs: { input: 'test' }
        ) do
          raise 'Test error'
        end
      end.to raise_error('Test error')

      expect(collector.size).to eq(1)
      trace = collector.traces.first
      expect(trace.error?).to be true
      expect(trace.metadata[:error]).to eq('Test error')
    end
  end
end

RSpec.describe 'Desiru::Core module methods' do
  describe '.trace_collector' do
    it 'returns a singleton trace collector' do
      collector1 = Desiru::Core.trace_collector
      collector2 = Desiru::Core.trace_collector

      expect(collector1).to be_a(Desiru::Core::TraceCollector)
      expect(collector1).to equal(collector2)
    end
  end

  describe '.trace_context' do
    it 'returns a singleton trace context' do
      context1 = Desiru::Core.trace_context
      context2 = Desiru::Core.trace_context

      expect(context1).to be_a(Desiru::Core::TraceContext)
      expect(context1).to equal(context2)
    end
  end

  describe '.reset_traces!' do
    it 'creates new collector and context instances' do
      old_collector = Desiru::Core.trace_collector
      old_context = Desiru::Core.trace_context

      Desiru::Core.reset_traces!

      new_collector = Desiru::Core.trace_collector
      new_context = Desiru::Core.trace_context

      expect(new_collector).not_to equal(old_collector)
      expect(new_context).not_to equal(old_context)
    end
  end
end
