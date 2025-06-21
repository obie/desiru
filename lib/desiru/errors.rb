# frozen_string_literal: true

module Desiru
  # Base error class moved here for organization
  class Error < StandardError
    attr_reader :context, :original_error

    def initialize(message = nil, context: {}, original_error: nil)
      @context = context
      @original_error = original_error

      super(build_message(message))
    end

    private

    def build_message(message)
      parts = [message || self.class.name.split('::').last]

      if context.any?
        context_str = context.map { |k, v| "#{k}: #{v}" }.join(', ')
        parts << "(#{context_str})"
      end

      parts << "caused by #{original_error.class}: #{original_error.message}" if original_error

      parts.join(' ')
    end
  end

  # Configuration errors
  class ConfigurationError < Error; end

  # Signature and validation errors
  class SignatureError < Error; end
  class ValidationError < Error; end

  # Module execution errors
  class ModuleError < Error; end
  class TimeoutError < ModuleError; end

  # Network and API errors
  class NetworkError < Error; end

  class RateLimitError < NetworkError
    attr_reader :retry_after

    def initialize(message = nil, retry_after: nil, **)
      @retry_after = retry_after
      super(message, **)
    end
  end

  class AuthenticationError < NetworkError; end

  # Model/LLM specific errors
  class ModelError < Error; end

  class TokenLimitError < ModelError
    attr_reader :token_count, :token_limit

    def initialize(message = nil, token_count: nil, token_limit: nil, **)
      @token_count = token_count
      @token_limit = token_limit
      super(message, **)
    end
  end

  class InvalidResponseError < ModelError; end
  class ModelNotAvailableError < ModelError; end

  # Job and async related errors
  class JobError < Error; end
  class JobNotFoundError < JobError; end
  class JobTimeoutError < JobError; end
  class JobFailedError < JobError; end

  # Persistence related errors
  class PersistenceError < Error; end
  class DatabaseConnectionError < PersistenceError; end
  class RecordNotFoundError < PersistenceError; end
  class RecordInvalidError < PersistenceError; end

  # Optimizer related errors
  class OptimizerError < Error; end
  class OptimizationFailedError < OptimizerError; end
  class InsufficientDataError < OptimizerError; end

  # Cache related errors
  class CacheError < Error; end
  class CacheConnectionError < CacheError; end

  # Error handling utilities
  module ErrorHandling
    # Wrap a block with error context
    def with_error_context(context = {})
      yield
    rescue StandardError => e
      # Add context to existing Desiru errors
      raise Desiru::Error.new(e.message, context: context, original_error: e) unless e.is_a?(Desiru::Error)

      e.context.merge!(context)
      raise e

      # Wrap other errors with context
    end

    # Retry with exponential backoff
    def with_retry(max_attempts: 3, backoff: :exponential, retriable_errors: [NetworkError, TimeoutError])
      attempt = 0

      begin
        attempt += 1
        yield(attempt)
      rescue *retriable_errors => e
        raise unless attempt < max_attempts

        delay = calculate_backoff(attempt, backoff)
        Desiru.logger.warn "Retrying after #{delay}s (attempt #{attempt}/#{max_attempts}): #{e.message}"
        sleep delay
        retry
      end
    end

    # Log and swallow errors (use sparingly)
    def safe_execute(default = nil, log_level: :error)
      yield
    rescue StandardError => e
      Desiru.logger.send(log_level, "Error in safe_execute: #{e.class} - #{e.message}")
      Desiru.logger.debug e.backtrace.join("\n") if log_level == :error
      default
    end

    private

    def calculate_backoff(attempt, strategy)
      case strategy
      when :exponential
        [2**(attempt - 1), 60].min # Max 60 seconds
      when :linear
        attempt * 2
      when Numeric
        strategy
      else
        1
      end
    end
  end

  # Include error handling in base classes
  class Module
    include ErrorHandling
  end

  module Jobs
    class Base
      include ErrorHandling
    end
  end
end
