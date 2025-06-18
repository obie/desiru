# frozen_string_literal: true

require_relative 'retry_strategies'

module Desiru
  module Jobs
    # Mixin for adding advanced retry capabilities to jobs
    module Retriable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        # Configure retry policy for the job class
        def retry_policy(policy = nil)
          if policy
            @retry_policy = policy
          else
            @retry_policy ||= RetryStrategies::RetryPolicy.new
          end
        end

        # DSL for configuring retry policy
        def configure_retries(max_retries: nil, strategy: nil, retriable: nil, non_retriable: nil)
          policy_options = {}
          policy_options[:max_retries] = max_retries if max_retries
          policy_options[:retry_strategy] = strategy if strategy
          policy_options[:retriable_errors] = retriable if retriable
          policy_options[:non_retriable_errors] = non_retriable if non_retriable
          
          @retry_policy = RetryStrategies::RetryPolicy.new(**policy_options)
        end
      end

      # Wrap job execution with retry logic
      def perform_with_retries(*args)
        retry_count = 0
        job_id = args.first if args.first.is_a?(String)

        begin
          # Track retry count in job result if persistence is enabled
          if job_id && respond_to?(:persistence_enabled?) && persistence_enabled?
            update_retry_count(job_id, retry_count)
          end

          perform_without_retries(*args)
        rescue => error
          policy = self.class.retry_policy

          if policy.should_retry?(retry_count, error)
            retry_count += 1
            delay = policy.retry_delay(retry_count)
            
            log_retry(error, retry_count, delay)
            
            # Schedule retry with delay
            self.class.perform_in(delay, *args)
          else
            # Max retries exceeded or non-retriable error
            log_retry_failure(error, retry_count)
            
            # Mark job as failed if persistence is enabled
            if job_id && respond_to?(:persist_error_to_db)
              persist_error_to_db(job_id, error, error.backtrace)
            end
            
            # Re-raise to let Sidekiq handle it
            raise
          end
        end
      end

      private

      def update_retry_count(job_id, count)
        return unless respond_to?(:job_repo) && job_repo

        job_result = job_repo.find_by_job_id(job_id)
        job_result&.update(retry_count: count)
      rescue StandardError => e
        Desiru.logger.warn("Failed to update retry count: #{e.message}")
      end

      def log_retry(error, retry_count, delay)
        Desiru.logger.warn(
          "Retrying #{self.class.name} after error: #{error.message}. " \
          "Retry #{retry_count}, waiting #{delay.round(2)}s"
        )
      end

      def log_retry_failure(error, retry_count)
        Desiru.logger.error(
          "#{self.class.name} failed after #{retry_count} retries: #{error.message}"
        )
      end
    end

    # Enhanced base job with retry capabilities
    class RetriableJob < Base
      include Retriable

      # Alias the original perform method
      alias_method :perform_without_retries, :perform
      alias_method :perform, :perform_with_retries

      # Default configuration with exponential backoff
      configure_retries(
        max_retries: 5,
        strategy: RetryStrategies::ExponentialBackoff.new,
        non_retriable: [
          ArgumentError,
          NoMethodError,
          SyntaxError
        ]
      )
    end
  end
end