# frozen_string_literal: true

require_relative 'async_capable'
require_relative 'assertions'

module Desiru
  # Base class for all Desiru modules
  # Implements the core module pattern with service-oriented design
  class Module
    extend Forwardable
    include AsyncCapable

    attr_reader :signature, :model, :config, :demos, :metadata

    def initialize(signature, model: nil, config: {}, demos: [], metadata: {})
      @signature = case signature
                   when Signature
                     signature
                   when String
                     Signature.new(signature)
                   else
                     raise ModuleError, 'Signature must be a String or Signature instance'
                   end

      @model = model || Desiru.configuration.default_model
      @config = default_config.merge(config)
      @demos = demos
      @metadata = metadata
      @call_count = 0

      # Raise error if no model available
      raise ArgumentError, 'No model provided and no default model configured' if @model.nil?

      validate_model!
      register_module
    end

    def call(inputs = {})
      @call_count += 1
      @retry_count = 0

      begin
        # Validate inputs first, then coerce
        signature.validate_inputs(inputs)
        coerced_inputs = signature.coerce_inputs(inputs)

        # Execute the module logic
        result = forward(**coerced_inputs)

        # Validate outputs first, then coerce
        signature.validate_outputs(result)
        coerced_outputs = signature.coerce_outputs(result)

        # Return result object
        ModuleResult.new(coerced_outputs, metadata: execution_metadata)
      rescue StandardError => e
        if should_retry?(e)
          @retry_count += 1
          log_retry(e)
          sleep(retry_delay_for(e))
          retry
        else
          handle_error(e)
        end
      end
    end

    def forward(_inputs)
      raise NotImplementedError, 'Subclasses must implement #forward'
    end

    def reset
      @demos = []
      @call_count = 0
    end

    def with_demos(new_demos)
      self.class.new(signature, model: model, config: config, demos: new_demos, metadata: metadata)
    end

    def to_h
      {
        class: self.class.name,
        signature: signature.to_h,
        config: config,
        demos_count: demos.size,
        call_count: @call_count,
        metadata: metadata
      }
    end

    protected

    def default_config
      {
        temperature: 0.7,
        max_tokens: 1000,
        timeout: 30,
        retry_on_failure: true
      }
    end

    def execution_metadata
      {
        module: self.class.name,
        call_count: @call_count,
        demos_used: demos.size,
        timestamp: Time.now
      }
    end

    private

    def should_retry?(error)
      return false unless config[:retry_on_failure]

      # Handle assertion errors specifically
      return error.retriable? && @retry_count < max_retries_for(error) if error.is_a?(Assertions::AssertionError)

      # Default retry logic for other errors
      @retry_count < Desiru.configuration.max_retries
    end

    def max_retries_for(error)
      if error.is_a?(Assertions::AssertionError)
        Assertions.configuration.max_assertion_retries
      else
        Desiru.configuration.max_retries
      end
    end

    def retry_delay_for(error)
      if error.is_a?(Assertions::AssertionError)
        Assertions.configuration.assertion_retry_delay
      else
        Desiru.configuration.retry_delay
      end
    end

    def log_retry(error)
      if error.is_a?(Assertions::AssertionError)
        Desiru.configuration.logger&.warn(
          "[ASSERTION RETRY] #{error.message} (attempt #{@retry_count}/#{max_retries_for(error)})"
        )
      else
        Desiru.configuration.logger&.warn(
          "Retrying module execution (attempt #{@retry_count}/#{Desiru.configuration.max_retries})"
        )
      end
    end

    def validate_model!
      return if model.nil? # Will use default

      # Skip validation for test doubles/mocks
      return if defined?(RSpec) && (model.is_a?(RSpec::Mocks::Double) || model.respond_to?(:_rspec_double))

      return if model.respond_to?(:complete)

      raise ConfigurationError, 'Model must respond to #complete'
    end

    def register_module
      # Auto-register with the registry if configured
      return unless Desiru.configuration.module_registry && metadata[:auto_register]

      Desiru.configuration.module_registry.register(
        self.class.name.split('::').last.downcase,
        self.class,
        metadata: metadata
      )
    end

    def handle_error(error)
      if error.is_a?(Assertions::AssertionError)
        # Update the assertion error with module context
        error.instance_variable_set(:@module_name, self.class.name)
        error.instance_variable_set(:@retry_count, @retry_count)

        Desiru.configuration.logger&.error(
          "[ASSERTION FAILED] #{error.message} in #{self.class.name} after #{@retry_count} retries"
        )
        raise error
      else
        Desiru.configuration.logger&.error("Module execution failed: #{error.message}")
        raise ModuleError, "Module execution failed: #{error.message}"
      end
    end
  end

  # Result object for module outputs
  class ModuleResult
    extend Forwardable

    attr_reader :data, :metadata, :outputs

    def_delegators :@data, :keys, :values, :each

    def initialize(data = nil, metadata: {}, **kwargs)
      # Support both positional and keyword arguments for backward compatibility
      if data.nil? && !kwargs.empty?
        @data = kwargs
        @outputs = kwargs
      else
        @data = data || {}
        @outputs = @data
      end
      @metadata = metadata
    end

    def [](key)
      if @data.key?(key.to_sym)
        @data[key.to_sym]
      elsif @data.key?(key.to_s)
        @data[key.to_s]
      end
    end

    def method_missing(method_name, *args, &)
      method_str = method_name.to_s
      if method_str.end_with?('?')
        # Handle predicate methods for boolean values
        key = method_str[0..-2].to_sym
        if data.key?(key)
          return !!data[key]
        elsif data.key?(key.to_s)
          return !!data[key.to_s]
        end
      end

      if data.key?(method_name.to_sym)
        data[method_name.to_sym]
      elsif data.key?(method_name.to_s)
        data[method_name.to_s]
      else
        super
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      method_str = method_name.to_s
      if method_str.end_with?('?')
        key = method_str[0..-2]
        data.key?(key.to_sym) || data.key?(key)
      else
        data.key?(method_name.to_sym) || data.key?(method_name.to_s) || super
      end
    end

    def to_h
      data
    end
  end
end
