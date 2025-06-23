# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Core::CompilationResult do
  let(:program) { double('Program', to_h: { name: 'TestProgram' }) }
  let(:metrics) { { optimization_score: 0.85, success_rate: 0.9 } }
  let(:traces) { [double('Trace'), double('Trace')] }
  let(:metadata) { { success: true, optimizer: 'TestOptimizer' } }

  describe '#initialize' do
    it 'creates a compilation result with all attributes' do
      result = described_class.new(
        program: program,
        metrics: metrics,
        traces: traces,
        metadata: metadata
      )

      expect(result.program).to eq(program)
      expect(result.metrics).to eq(metrics)
      expect(result.traces).to eq(traces)
      expect(result.metadata).to eq(metadata)
    end
  end

  describe '#success?' do
    it 'returns true when success is not false' do
      result = described_class.new(program: program, metadata: { success: true })
      expect(result.success?).to be true
    end

    it 'returns false when success is false' do
      result = described_class.new(program: program, metadata: { success: false })
      expect(result.success?).to be false
    end

    it 'returns true when success is not specified' do
      result = described_class.new(program: program)
      expect(result.success?).to be true
    end
  end

  describe '#optimization_score' do
    it 'returns the optimization score from metrics' do
      result = described_class.new(program: program, metrics: { optimization_score: 0.75 })
      expect(result.optimization_score).to eq(0.75)
    end

    it 'returns 0.0 when no optimization score' do
      result = described_class.new(program: program)
      expect(result.optimization_score).to eq(0.0)
    end
  end

  describe '#to_h' do
    it 'returns a hash representation' do
      result = described_class.new(
        program: program,
        metrics: metrics,
        traces: traces,
        metadata: metadata
      )

      hash = result.to_h
      expect(hash[:program]).to eq({ name: 'TestProgram' })
      expect(hash[:metrics]).to eq(metrics)
      expect(hash[:traces_count]).to eq(2)
      expect(hash[:metadata]).to eq(metadata)
    end
  end
end

RSpec.describe Desiru::Core::Compiler do
  let(:optimizer) { double('Optimizer') }
  let(:trace_collector) { Desiru::Core::TraceCollector.new }
  let(:compiler) { described_class.new(optimizer: optimizer, trace_collector: trace_collector) }

  # Create test module and program classes
  let(:test_module) do
    double('Module',
           signature: "question -> answer",
           enable_trace!: nil,
           disable_trace!: nil,
           with_demos: double('Module'))
  end

  let(:test_program) do
    double('Program',
           modules: [test_module],
           to_h: { name: 'TestProgram' },
           dup: double('Program', modules: [test_module], update_module: nil))
  end

  describe '#initialize' do
    it 'creates a compiler with optimizer and trace collector' do
      expect(compiler.optimizer).to eq(optimizer)
      expect(compiler.trace_collector).to eq(trace_collector)
    end

    it 'uses default trace collector if not provided' do
      compiler = described_class.new(optimizer: optimizer)
      expect(compiler.trace_collector).to eq(Desiru::Core.trace_collector)
    end

    it 'merges provided config with defaults' do
      compiler = described_class.new(config: { max_demos: 10 })
      expect(compiler.config[:max_demos]).to eq(10)
      expect(compiler.config[:clear_traces]).to be true
    end
  end

  describe '#compile' do
    let(:training_set) { [Desiru::Core::Example.new(question: 'Q1', answer: 'A1')] }

    context 'with optimizer' do
      it 'uses optimizer to compile program' do
        optimized_program = double('OptimizedProgram',
                                   modules: [test_module],
                                   to_h: { name: 'OptimizedProgram' })

        allow(optimizer).to receive(:optimize).with(test_program, training_set).and_return(optimized_program)

        result = compiler.compile(test_program, training_set)

        expect(result).to be_a(Desiru::Core::CompilationResult)
        expect(result.program).to eq(optimized_program)
        expect(result.success?).to be true
        expect(result.metadata[:optimizer]).to eq(optimizer.class.name)
      end
    end

    context 'without optimizer' do
      let(:compiler) { described_class.new(trace_collector: trace_collector) }

      it 'performs basic compilation without optimization' do
        result = compiler.compile(test_program, training_set)

        expect(result).to be_a(Desiru::Core::CompilationResult)
        expect(result.success?).to be true
        expect(result.metadata[:optimizer]).to be_nil
      end
    end

    it 'clears traces before compilation' do
      trace_collector.collect(Desiru::Core::Trace.new(
                                module_name: 'OldModule',
                                signature: "input -> output"
                              ))

      expect(trace_collector).not_to be_empty

      allow(optimizer).to receive(:optimize).and_return(test_program)
      compiler.compile(test_program, training_set)

      expect(trace_collector).to be_empty
    end

    it 'enables tracing on modules' do
      allow(optimizer).to receive(:optimize).and_return(test_program)

      expect(test_module).to receive(:enable_trace!)

      compiler.compile(test_program, training_set)
    end

    it 'handles compilation errors gracefully' do
      allow(optimizer).to receive(:optimize).and_raise('Optimization failed')

      result = compiler.compile(test_program, training_set)

      expect(result.success?).to be false
      expect(result.metadata[:error]).to eq('Optimization failed')
      expect(result.program).to eq(test_program)
    end

    it 'restores trace state after compilation' do
      allow(optimizer).to receive(:optimize).and_return(test_program)

      expect(test_module).to receive(:disable_trace!)

      compiler.compile(test_program, training_set)
    end

    it 'collects metrics during compilation' do
      allow(optimizer).to receive(:optimize) do
        # Add traces during optimization (after clear)
        3.times do
          trace_collector.collect(Desiru::Core::Trace.new(
                                    module_name: 'TestModule',
                                    signature: "input -> output",
                                    metadata: { success: true }
                                  ))
        end

        # Add a failed trace
        trace_collector.collect(Desiru::Core::Trace.new(
                                  module_name: 'TestModule',
                                  signature: "input -> output",
                                  metadata: { success: false }
                                ))

        test_program
      end

      result = compiler.compile(test_program, training_set)

      expect(result.metrics[:success_rate]).to eq(0.75)
      expect(result.metrics[:optimization_score]).to eq(0.75)
      expect(result.metrics[:traces_collected]).to eq(4)
    end
  end

  describe '#compile_module' do
    let(:examples) do
      [
        Desiru::Core::Example.new(question: 'Q1', answer: 'A1'),
        Desiru::Core::Example.new(question: 'Q2', answer: 'A2')
      ]
    end

    it 'returns module unchanged when no examples' do
      result = compiler.compile_module(test_module, [])
      expect(result).to eq(test_module)
    end

    it 'creates new module with demos from examples' do
      new_module = double('ModuleWithDemos')
      allow(test_module).to receive(:with_demos).with(examples).and_return(new_module)

      result = compiler.compile_module(test_module, examples)
      expect(result).to eq(new_module)
    end

    it 'limits demos to max_demos config' do
      compiler = described_class.new(config: { max_demos: 1 })

      limited_examples = [examples.first]
      new_module = double('ModuleWithDemos')
      allow(test_module).to receive(:with_demos).with(limited_examples).and_return(new_module)

      result = compiler.compile_module(test_module, examples)
      expect(result).to eq(new_module)
    end
  end
end

RSpec.describe Desiru::Core::CompilerBuilder do
  describe 'builder pattern' do
    it 'builds a compiler with all options' do
      optimizer = double('Optimizer')
      collector = double('TraceCollector')

      compiler = described_class.new
                                .with_optimizer(optimizer)
                                .with_trace_collector(collector)
                                .with_config(max_demos: 10)
                                .build

      expect(compiler).to be_a(Desiru::Core::Compiler)
      expect(compiler.optimizer).to eq(optimizer)
      expect(compiler.trace_collector).to eq(collector)
      expect(compiler.config[:max_demos]).to eq(10)
    end

    it 'supports method chaining' do
      builder = described_class.new

      expect(builder.with_optimizer(double)).to eq(builder)
      expect(builder.with_trace_collector(double)).to eq(builder)
      expect(builder.with_config({})).to eq(builder)
    end
  end
end
