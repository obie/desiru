# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Compilation Infrastructure Integration' do
  let(:mock_signature) do
    double('Signature',
           to_h: { input_fields: { text: :string }, output_fields: { result: :string } },
           input_fields: { text: double(type: :string) },
           output_fields: { result: double(type: :string) })
  end

  let(:mock_module) do
    double('Module',
           signature: mock_signature,
           class: double(name: 'MockModule'),
           with_demos: double('ModuleWithDemos'),
           enable_trace!: nil,
           disable_trace!: nil,
           respond_to?: true)
  end

  let(:mock_program) do
    double('Program',
           modules: [mock_module],
           dup: double('DuplicatedProgram',
                       modules: [mock_module],
                       update_module: nil),
           to_h: { modules: ['MockModule'] })
  end

  let(:training_examples) do
    [
      Desiru::Core::Example.new(text: "Hello", result: "Hi there"),
      Desiru::Core::Example.new(text: "Goodbye", result: "See you later"),
      Desiru::Core::Example.new(text: "Thanks", result: "You're welcome")
    ]
  end

  before do
    Desiru::Core.reset_traces!
  end

  describe 'CompilationResult' do
    it 'creates valid compilation results' do
      result = Desiru::Core::CompilationResult.new(
        program: mock_program,
        metrics: { score: 0.85 },
        traces: [],
        metadata: { success: true }
      )

      expect(result.program).to eq(mock_program)
      expect(result.metrics[:score]).to eq(0.85)
      expect(result.success?).to be(true)
      expect(result.optimization_score).to eq(0.0) # Default when no optimization_score metric
    end

    it 'handles failed compilation results' do
      result = Desiru::Core::CompilationResult.new(
        program: mock_program,
        metadata: { success: false, error: 'Compilation failed' }
      )

      expect(result.success?).to be(false)
      expect(result.metadata[:error]).to eq('Compilation failed')
    end

    it 'serializes to hash correctly' do
      result = Desiru::Core::CompilationResult.new(
        program: mock_program,
        metrics: { score: 0.9 },
        traces: [1, 2, 3], # Mock traces
        metadata: { optimizer: 'TestOptimizer' }
      )

      hash = result.to_h

      expect(hash).to include(
        program: { modules: ['MockModule'] },
        metrics: { score: 0.9 },
        traces_count: 3,
        metadata: { optimizer: 'TestOptimizer' }
      )
    end
  end

  describe 'Compiler basic functionality' do
    let(:compiler) { Desiru::Core::Compiler.new }

    it 'compiles programs without optimization' do
      result = compiler.compile(mock_program, training_examples)

      expect(result).to be_a(Desiru::Core::CompilationResult)
      expect(result.success?).to be(true)
      expect(result.metrics[:training_set_size]).to eq(3)
      expect(result.metadata[:optimizer]).to be_nil
    end

    it 'handles compilation errors gracefully' do
      failing_program = double('FailingProgram')
      allow(failing_program).to receive(:modules).and_raise(StandardError.new('Program error'))

      result = compiler.compile(failing_program, [])

      expect(result.success?).to be(false)
      expect(result.metadata[:error]).to eq('Program error')
      expect(result.metadata[:error_class]).to eq('StandardError')
    end

    it 'manages trace collection during compilation' do
      # Add some traces to the collector
      trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: { text: 'test' },
        outputs: { result: 'processed' }
      )

      Desiru::Core.trace_collector.collect(trace)
      expect(Desiru::Core.trace_collector.size).to eq(1)

      # Create compiler that doesn't clear traces
      no_clear_compiler = Desiru::Core::Compiler.new(config: { clear_traces: false })
      result = no_clear_compiler.compile(mock_program, [])

      expect(result.traces.size).to eq(1)
      expect(result.metrics[:traces_collected]).to eq(1)
    end

    it 'clears traces when configured' do
      # Add trace before compilation
      trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: { text: 'test' },
        outputs: { result: 'processed' }
      )

      Desiru::Core.trace_collector.collect(trace)
      expect(Desiru::Core.trace_collector.size).to eq(1)

      compiler_with_clear = Desiru::Core::Compiler.new(config: { clear_traces: true })
      result = compiler_with_clear.compile(mock_program, [])

      # Trace collector should be cleared
      expect(Desiru::Core.trace_collector.size).to eq(0)
      expect(result.success?).to be(true)
    end

    it 'does not clear traces when configured not to' do
      trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: { text: 'test' },
        outputs: { result: 'processed' }
      )

      Desiru::Core.trace_collector.collect(trace)

      compiler_no_clear = Desiru::Core::Compiler.new(config: { clear_traces: false })
      result = compiler_no_clear.compile(mock_program, [])

      expect(Desiru::Core.trace_collector.size).to eq(1)
      expect(result.success?).to be(true)
    end
  end

  describe 'Compiler with optimizer integration' do
    let(:mock_optimizer) do
      double('Optimizer',
             class: double(name: 'MockOptimizer'),
             optimize: mock_program)
    end

    let(:compiler_with_optimizer) do
      Desiru::Core::Compiler.new(optimizer: mock_optimizer)
    end

    it 'uses optimizer when provided' do
      expect(mock_optimizer).to receive(:optimize).with(mock_program, training_examples)

      result = compiler_with_optimizer.compile(mock_program, training_examples)

      expect(result.success?).to be(true)
      expect(result.metadata[:optimizer]).to eq('MockOptimizer')
    end

    it 'handles optimizer failures' do
      allow(mock_optimizer).to receive(:optimize).and_raise(StandardError.new('Optimizer failed'))

      result = compiler_with_optimizer.compile(mock_program, training_examples)

      expect(result.success?).to be(false)
      expect(result.metadata[:error]).to eq('Optimizer failed')
    end

    it 'passes correct parameters to optimizer' do
      expect(mock_optimizer).to receive(:optimize).with(mock_program, training_examples).and_return(mock_program)

      compiler_with_optimizer.compile(mock_program, training_examples)
    end
  end

  describe 'Module compilation' do
    let(:compiler) { Desiru::Core::Compiler.new(config: { max_demos: 2 }) }

    it 'compiles individual modules with examples' do
      compiled_module = double('CompiledModule')
      allow(mock_module).to receive(:with_demos).with(training_examples.first(2)).and_return(compiled_module)

      result = compiler.compile_module(mock_module, training_examples)

      expect(result).to eq(compiled_module)
    end

    it 'returns original module when no examples provided' do
      result = compiler.compile_module(mock_module, [])

      expect(result).to eq(mock_module)
    end

    it 'respects max_demos configuration' do
      expect(mock_module).to receive(:with_demos).with(training_examples.first(2))

      compiler.compile_module(mock_module, training_examples)
    end

    it 'filters out non-Example objects' do
      mixed_examples = [
        training_examples.first,
        "not an example",
        training_examples.last,
        { not: "an example" }
      ]

      expect(mock_module).to receive(:with_demos) do |demos|
        expect(demos.size).to eq(2)
        expect(demos.all? { |d| d.is_a?(Desiru::Core::Example) }).to be(true)
        mock_module
      end

      compiler.compile_module(mock_module, mixed_examples)
    end
  end

  describe 'Metrics collection' do
    let(:compiler) { Desiru::Core::Compiler.new(config: { evaluate_metrics: true, clear_traces: false }) }

    it 'collects comprehensive metrics' do
      # Add some traces with different success states
      successful_trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: { text: 'test' },
        outputs: { result: 'success' },
        metadata: { success: true }
      )

      failed_trace = Desiru::Core::Trace.new(
        module_name: 'TestModule',
        signature: mock_signature,
        inputs: { text: 'test' },
        outputs: {},
        metadata: { success: false, error: 'failed' }
      )

      Desiru::Core.trace_collector.collect(successful_trace)
      Desiru::Core.trace_collector.collect(failed_trace)

      result = compiler.compile(mock_program, training_examples)

      expect(result.metrics).to include(
        training_set_size: 3,
        traces_collected: 2,
        success_rate: 0.5,
        optimization_score: 0.5
      )
      expect(result.metrics[:compilation_duration]).to be > 0
    end

    it 'skips metrics when configured not to evaluate' do
      no_metrics_compiler = Desiru::Core::Compiler.new(config: { evaluate_metrics: false })

      result = no_metrics_compiler.compile(mock_program, training_examples)

      expect(result.metrics.keys).to contain_exactly(:compilation_duration)
    end

    it 'handles empty trace collector gracefully' do
      result = compiler.compile(mock_program, training_examples)

      expect(result.metrics).to include(
        training_set_size: 3,
        traces_collected: 0
      )
      expect(result.metrics).not_to have_key(:success_rate)
    end
  end

  describe 'CompilerBuilder' do
    it 'builds compiler with all components' do
      mock_optimizer = double('Optimizer')
      mock_collector = double('TraceCollector')
      config = { custom: 'value' }

      compiler = Desiru::Core::CompilerBuilder.new
                                              .with_optimizer(mock_optimizer)
                                              .with_trace_collector(mock_collector)
                                              .with_config(config)
                                              .build

      expect(compiler.optimizer).to eq(mock_optimizer)
      expect(compiler.trace_collector).to eq(mock_collector)
      expect(compiler.config[:custom]).to eq('value')
    end

    it 'builds compiler with defaults when components not provided' do
      compiler = Desiru::Core::CompilerBuilder.new.build

      expect(compiler.optimizer).to be_nil
      expect(compiler.trace_collector).to eq(Desiru::Core.trace_collector)
      expect(compiler.config).to include(
        clear_traces: true,
        restore_trace_state: true,
        max_demos: 5,
        evaluate_metrics: true
      )
    end

    it 'supports method chaining' do
      builder = Desiru::Core::CompilerBuilder.new

      result = builder
               .with_optimizer(double('Optimizer'))
               .with_config({ test: true })

      expect(result).to be(builder)
    end
  end

  describe 'End-to-end compilation scenarios' do
    it 'handles complex compilation with real-like components' do
      # Create a more realistic program structure
      program_class = Class.new do
        attr_reader :modules

        def initialize(modules)
          @modules = modules
        end

        def dup
          self.class.new(@modules.dup)
        end

        def update_module(mod_class, new_module)
          @modules.map! { |m| m.instance_of?(mod_class) ? new_module : m }
        end

        def to_h
          { modules: @modules.map(&:class).map(&:name) }
        end
      end

      module_class = Class.new do
        attr_reader :signature, :demos

        def initialize(demos: [])
          @signature = "text: string -> result: string"
          @demos = demos
        end

        def with_demos(new_demos)
          self.class.new(demos: new_demos)
        end

        def enable_trace!
          @trace_enabled = true
        end

        def disable_trace!
          @trace_enabled = false
        end

        def respond_to?(method)
          %i[enable_trace! disable_trace! with_demos].include?(method) || super
        end
      end

      modules = [module_class.new, module_class.new]
      program = program_class.new(modules)

      compiler = Desiru::Core::Compiler.new(config: { max_demos: 2 })
      result = compiler.compile(program, training_examples)

      expect(result.success?).to be(true)
      expect(result.program).to be_a(program_class)
      expect(result.metrics[:training_set_size]).to eq(3)
    end

    it 'integrates trace collection with compilation lifecycle' do
      trace_enabled_program = double('Program')
      trace_enabled_module = double('Module')

      allow(trace_enabled_program).to receive(:modules).and_return([trace_enabled_module])
      allow(trace_enabled_program).to receive(:dup).and_return(trace_enabled_program)
      allow(trace_enabled_program).to receive(:to_h).and_return({ modules: ['TestModule'] })

      allow(trace_enabled_module).to receive_messages(
        enable_trace!: nil,
        disable_trace!: nil,
        respond_to?: true,
        signature: mock_signature,
        class: double(name: 'TestModule'),
        with_demos: trace_enabled_module
      )

      # Simulate module execution during compilation that generates traces
      allow(trace_enabled_module).to receive(:enable_trace!) do
        Desiru::Core.trace_collector.collect(
          Desiru::Core::Trace.new(
            module_name: 'TestModule',
            signature: mock_signature,
            inputs: { text: 'compilation test' },
            outputs: { result: 'compiled' }
          )
        )
      end

      compiler = Desiru::Core::Compiler.new(
        config: { clear_traces: true, restore_trace_state: true }
      )

      result = compiler.compile(trace_enabled_program, [])

      expect(result.success?).to be(true)
      expect(result.traces.size).to eq(1)
      expect(result.traces.first.module_name).to eq('TestModule')
      expect(trace_enabled_module).to have_received(:enable_trace!)
      expect(trace_enabled_module).to have_received(:disable_trace!)
    end
  end

  describe 'Error handling and edge cases' do
    let(:compiler) { Desiru::Core::Compiler.new }

    it 'handles programs with no modules' do
      empty_program = double('EmptyProgram',
                             modules: [],
                             dup: double('DuplicatedProgram', modules: []),
                             to_h: { modules: [] })

      result = compiler.compile(empty_program, [])

      expect(result.success?).to be(true)
      expect(result.metrics[:original_modules_count]).to eq(0)
    end

    it 'handles modules that do not support tracing' do
      non_traceable_module = double('NonTraceableModule',
                                    respond_to?: false,
                                    signature: mock_signature,
                                    class: double(name: 'NonTraceableModule'),
                                    with_demos: double('ModuleWithDemos'))

      non_traceable_program = double('Program',
                                     modules: [non_traceable_module],
                                     dup: double('DuplicatedProgram',
                                                 modules: [non_traceable_module],
                                                 update_module: nil),
                                     to_h: { modules: ['NonTraceableModule'] })

      result = compiler.compile(non_traceable_program, [])

      expect(result.success?).to be(true)
    end

    it 'maintains compilation stack integrity even with nested errors' do
      failing_program = double('Program')
      allow(failing_program).to receive(:modules).and_raise('Outer error')

      # Simulate nested compilation calls
      expect do
        compiler.compile(failing_program, [])
      end.not_to raise_error

      # Should be able to compile successfully after error
      result = compiler.compile(mock_program, [])
      expect(result.success?).to be(true)
    end
  end
end
