# frozen_string_literal: true

module Desiru
  # Assertion system for validating module outputs
  module Assertions
    # Error raised when an assertion fails
    class AssertionError < StandardError
      attr_reader :module_name, :retry_count

      def initialize(message = nil, module_name: nil, retry_count: 0)
        super(message)
        @module_name = module_name
        @retry_count = retry_count
      end

      # Assertions should trigger module retries
      def retriable?
        true
      end
    end

    # Assert that a condition is true, raising AssertionError if false
    # @param condition [Boolean] The condition to check
    # @param message [String] Optional error message
    # @raise [AssertionError] if condition is false
    def self.assert(condition, message = nil)
      return if condition

      message ||= 'Assertion failed'
      raise AssertionError, message
    end

    # Suggest that a condition should be true, logging a warning if false
    # @param condition [Boolean] The condition to check
    # @param message [String] Optional warning message
    def self.suggest(condition, message = nil)
      return if condition

      message ||= 'Suggestion failed'
      Desiru.logger.warn("[SUGGESTION] #{message}")
    end

    # Configuration for assertion behavior
    class Configuration
      attr_accessor :max_assertion_retries, :assertion_retry_delay
      attr_accessor :log_assertions, :track_assertion_metrics

      def initialize
        @max_assertion_retries = 3
        @assertion_retry_delay = 0.1 # seconds
        @log_assertions = true
        @track_assertion_metrics = false
      end
    end

    # Get or set the assertion configuration
    def self.configuration
      @configuration ||= Configuration.new
    end

    # Configure assertion behavior
    def self.configure
      yield(configuration) if block_given?
    end
  end

  # Module-level convenience methods
  def self.assert(condition, message = nil)
    Assertions.assert(condition, message)
  end

  def self.suggest(condition, message = nil)
    Assertions.suggest(condition, message)
  end
end