# frozen_string_literal: true

module Desiru
  module Models
    # Base adapter class for language model integrations
    # Defines the interface all model adapters must implement
    class Base
      attr_reader :config, :client

      def initialize(config = {})
        @config = default_config.merge(config)
        @client = build_client
        @request_count = 0
        @token_count = 0

        validate_config!
      end

      # Main interface method - must be implemented by subclasses
      def complete(prompt, **options)
        raise NotImplementedError, 'Subclasses must implement #complete'
      end

      # Stream completion - optional implementation
      def stream_complete(prompt, **options, &)
        raise NotImplementedError, "Streaming not supported by #{self.class.name}"
      end

      # Get available models
      def models
        raise NotImplementedError, 'Subclasses must implement #models'
      end

      # Health check
      def healthy?
        models
        true
      rescue StandardError
        false
      end

      # Usage statistics
      def stats
        {
          request_count: @request_count,
          token_count: @token_count,
          model: config[:model]
        }
      end

      def reset_stats
        @request_count = 0
        @token_count = 0
      end

      protected

      def default_config
        {
          model: nil,
          temperature: 0.7,
          max_tokens: 1000,
          timeout: 30,
          retry_on_failure: true,
          max_retries: 3
        }
      end

      def build_client
        # Override in subclasses to build the actual client
        nil
      end

      def validate_config!
        # Override in subclasses for specific validation
      end

      def increment_stats(tokens_used = 0)
        @request_count += 1
        @token_count += tokens_used
      end

      # Common error handling
      def with_retry(max_attempts = nil)
        max_attempts ||= config[:max_retries]
        attempts = 0

        begin
          attempts += 1
          yield
        rescue StandardError => e
          raise unless attempts < max_attempts && retryable_error?(e)

          sleep(retry_delay(attempts))
          retry
        end
      end

      def retryable_error?(error)
        # Override in subclasses for specific error types
        error.message.include?('timeout') || error.message.include?('rate limit')
      end

      def retry_delay(attempt)
        # Exponential backoff with jitter
        base_delay = 2**attempt
        jitter = rand(0..1.0)
        base_delay + jitter
      end
    end
  end
end
