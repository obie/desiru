# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Core::Traceable do
  # Create a test module class
  let(:test_module_class) do
    Class.new(Desiru::Module) do
      def forward(inputs)
        { result: inputs[:value] * 2 }
      end
    end
  end

  let(:signature) { Desiru::Signature.new('value: integer -> result: integer') }
  let(:model) { double('Model', call: { response: 'test' }) }

  before do
    # Traceable is already included via Module base class
    Desiru::Core.reset_traces!
  end

  describe 'trace collection' do
    it 'collects traces when calling a module' do
      mod = test_module_class.new(signature, model: model)
      mod.call(value: 5)

      expect(Desiru::Core.trace_collector.size).to eq(1)

      trace = Desiru::Core.trace_collector.traces.first
      expect(trace.module_name).to eq("AnonymousModule") # Anonymous classes have no name
      expect(trace.inputs).to eq({ value: 5 })
      expect(trace.outputs).to eq({ result: 10 })
      expect(trace.success?).to be true
    end

    it 'captures errors in traces' do
      error_module_class = Class.new(Desiru::Module) do
        def forward(_inputs)
          raise 'Test error'
        end
      end
      # Traceable is already included via Module base class

      mod = error_module_class.new(signature, model: model)

      expect { mod.call(value: 5) }.to raise_error(Desiru::ModuleError, 'Module execution failed: Test error')
      expect(Desiru::Core.trace_collector.size).to eq(1)

      trace = Desiru::Core.trace_collector.traces.first
      expect(trace.error?).to be true
      expect(trace.metadata[:error]).to eq('Module execution failed: Test error')
      expect(trace.success?).to be false
    end

    it 'respects trace_enabled? setting' do
      mod = test_module_class.new(signature, model: model)
      mod.disable_trace!

      mod.call(value: 5)
      expect(Desiru::Core.trace_collector.empty?).to be true

      mod.enable_trace!
      mod.call(value: 5)
      expect(Desiru::Core.trace_collector.size).to eq(1)
    end
  end

  describe 'ModuleResult handling' do
    it 'extracts outputs and metadata from ModuleResult' do
      # Create a module that returns a ModuleResult
      module_result_class = Class.new(Desiru::Module) do
        def forward(inputs)
          { result: inputs[:value] * 2 }
        end
      end
      # Traceable is already included via Module base class

      mod = module_result_class.new(signature, model: model)
      mod.call(value: 5)

      trace = Desiru::Core.trace_collector.traces.first
      expect(trace.outputs).to eq({ result: 10 })
      expect(trace.metadata).to include(:success)
    end
  end

  describe '#trace_enabled?' do
    let(:mod) { test_module_class.new(signature, model: model) }

    it 'defaults to true' do
      expect(mod.trace_enabled?).to be true
    end

    it 'can be disabled' do
      mod.disable_trace!
      expect(mod.trace_enabled?).to be false
    end

    it 'can be re-enabled' do
      mod.disable_trace!
      mod.enable_trace!
      expect(mod.trace_enabled?).to be true
    end
  end
end
