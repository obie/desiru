# frozen_string_literal: true

module Desiru
  module Core
    class CompilationResult
      attr_reader :program, :metrics, :traces, :metadata

      def initialize(program:, metrics: {}, traces: [], metadata: {})
        @program = program
        @metrics = metrics
        @traces = traces
        @metadata = metadata
      end

      def success?
        @metadata[:success] != false
      end

      def optimization_score
        @metrics[:optimization_score] || 0.0
      end

      def to_h
        {
          program: @program.to_h,
          metrics: @metrics,
          traces_count: @traces.size,
          metadata: @metadata
        }
      end
    end

    class Compiler
      attr_reader :optimizer, :trace_collector, :config

      def initialize(optimizer: nil, trace_collector: nil, config: {})
        @optimizer = optimizer
        @trace_collector = trace_collector || Core.trace_collector
        @config = default_config.merge(config)
        @compilation_stack = []
      end

      def compile(program, training_set = [])
        start_compilation(program)
        modules_traced = false

        begin
          # Clear previous traces if configured
          @trace_collector.clear if @config[:clear_traces]

          # Enable tracing for all modules
          enable_module_tracing(program)
          modules_traced = true

          # Run optimizer if provided
          if @optimizer
            if @optimizer.respond_to?(:compile)
              # MIPROv2 style optimizer
              optimized_program = @optimizer.compile(program, trainset: training_set)
            elsif @optimizer.respond_to?(:optimize)
              # Generic optimizer
              optimized_program = @optimizer.optimize(program, training_set)
            else
              raise ArgumentError, "Optimizer must implement either compile or optimize method"
            end
          else
            # Basic compilation without optimization
            optimized_program = compile_without_optimization(program, training_set)
          end

          # Collect compilation metrics
          metrics = collect_metrics(program, optimized_program, training_set)

          # Get relevant traces
          traces = @trace_collector.traces.dup

          end_compilation(
            program: optimized_program,
            metrics: metrics,
            traces: traces,
            metadata: { success: true, optimizer: @optimizer&.class&.name }
          )
        rescue StandardError => e
          end_compilation(
            program: program,
            metrics: {},
            traces: @trace_collector.respond_to?(:traces) ? @trace_collector.traces.dup : [],
            metadata: { success: false, error: e.message, error_class: e.class.name }
          )
        ensure
          disable_module_tracing(program) if @config[:restore_trace_state] && modules_traced
        end
      end

      def compile_module(mod, examples = [])
        # Compile individual module with examples
        return mod if examples.empty?

        # Extract demonstrations from successful examples
        demos = examples.select { |ex| ex.is_a?(Example) }.take(@config[:max_demos])

        # Create new module instance with demos
        mod.with_demos(demos)
      end

      private

      def default_config
        {
          clear_traces: true,
          restore_trace_state: true,
          max_demos: 5,
          evaluate_metrics: true
        }
      end

      def start_compilation(program)
        @compilation_stack.push({
                                  program: program,
                                  start_time: Time.now
                                })
      end

      def end_compilation(program:, metrics:, traces:, metadata:)
        compilation_data = @compilation_stack.pop
        duration = Time.now - compilation_data[:start_time]

        CompilationResult.new(
          program: program,
          metrics: metrics.merge(compilation_duration: duration),
          traces: traces,
          metadata: metadata
        )
      end

      def enable_module_tracing(program)
        return unless program.respond_to?(:modules)

        program.modules.each do |mod|
          mod.enable_trace! if mod.respond_to?(:enable_trace!)
        end
      end

      def disable_module_tracing(program)
        return unless program.respond_to?(:modules)

        program.modules.each do |mod|
          mod.disable_trace! if mod.respond_to?(:disable_trace!)
        end
      end

      def compile_without_optimization(program, training_set)
        # Basic compilation: collect examples as demonstrations
        return program if training_set.empty? || !program.respond_to?(:modules)

        # Create a copy of the program
        compiled_program = program.dup

        # Update modules with training examples if program supports it
        if compiled_program.respond_to?(:modules) && compiled_program.respond_to?(:update_module)
          compiled_program.modules.each do |mod|
            next unless mod.respond_to?(:signature) && mod.signature.respond_to?(:input_fields)

            relevant_examples = training_set.select do |ex|
              ex.respond_to?(:keys) && ex.keys.any? { |k| mod.signature.input_fields.key?(k) }
            end

            compiled_module = compile_module(mod, relevant_examples)
            compiled_program.update_module(mod.class, compiled_module) if compiled_module
          end
        end

        compiled_program
      end

      def collect_metrics(original_program, optimized_program, training_set)
        return { compilation_duration: 0 } unless @config[:evaluate_metrics]

        metrics = {
          training_set_size: training_set.size,
          traces_collected: @trace_collector.size
        }

        # Add module counts if available
        metrics[:original_modules_count] = original_program.modules.size if original_program.respond_to?(:modules)

        metrics[:optimized_modules_count] = optimized_program.modules.size if optimized_program.respond_to?(:modules)

        # Add success rate if traces available
        if @trace_collector.size > 0
          success_rate = @trace_collector.successful.size.to_f / @trace_collector.size
          metrics[:success_rate] = success_rate
          metrics[:optimization_score] = success_rate
        end

        metrics
      end
    end

    class CompilerBuilder
      def initialize
        @optimizer = nil
        @trace_collector = nil
        @config = {}
      end

      def with_optimizer(optimizer)
        @optimizer = optimizer
        self
      end

      def with_trace_collector(collector)
        @trace_collector = collector
        self
      end

      def with_config(config)
        @config.merge!(config)
        self
      end

      def build
        Compiler.new(
          optimizer: @optimizer,
          trace_collector: @trace_collector,
          config: @config
        )
      end
    end
  end
end
