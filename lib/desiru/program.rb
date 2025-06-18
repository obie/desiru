# frozen_string_literal: true

module Desiru
  # Base class for composing multiple modules into programs
  # Implements composition patterns for complex AI workflows
  class Program
    attr_reader :modules, :config, :metadata

    def initialize(config: {}, metadata: {})
      @modules = {}
      @config = default_config.merge(config)
      @metadata = metadata
      @execution_trace = []

      setup_modules
    end

    def call(inputs = {})
      @execution_trace.clear
      start_time = Time.now

      result = forward(inputs)

      execution_time = Time.now - start_time

      ProgramResult.new(
        result,
        metadata: {
          execution_time: execution_time,
          trace: @execution_trace.dup,
          program: self.class.name
        }
      )
    rescue StandardError => e
      handle_error(e)
    end

    def forward(_inputs)
      raise NotImplementedError, 'Subclasses must implement #forward'
    end

    def reset
      modules.each_value(&:reset)
      @execution_trace.clear
    end

    def optimize(optimizer, trainset, valset = nil)
      optimizer.compile(self, trainset: trainset, valset: valset)
    end

    def to_h
      {
        class: self.class.name,
        modules: modules.transform_values(&:to_h),
        config: config,
        metadata: metadata
      }
    end

    protected

    def setup_modules
      # Override in subclasses to initialize modules
    end

    def trace_execution(module_name, inputs, outputs)
      @execution_trace << {
        module: module_name,
        inputs: inputs,
        outputs: outputs.is_a?(ModuleResult) ? outputs.to_h : outputs,
        timestamp: Time.now
      }
    end

    def default_config
      {
        max_iterations: 10,
        early_stopping: true,
        trace_execution: true
      }
    end

    private

    def handle_error(error)
      Desiru.configuration.logger&.error("Program execution failed: #{error.message}")

      # Programs don't retry by default - let individual modules handle retries
      raise ProgramError, "Program execution failed: #{error.message}"
    end
  end

  # Result object for program outputs
  class ProgramResult < ModuleResult
    def trace
      metadata[:trace] || []
    end

    def execution_time
      metadata[:execution_time]
    end
  end

  # Base error for program-related issues
  class ProgramError < Error; end
end
