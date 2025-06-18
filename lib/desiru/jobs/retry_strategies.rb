# frozen_string_literal: true

module Desiru
  module Jobs
    # Advanced retry strategies for background jobs
    module RetryStrategies
      # Exponential backoff with jitter
      class ExponentialBackoff
        attr_reader :base_delay, :max_delay, :multiplier, :jitter

        def initialize(base_delay: 1, max_delay: 300, multiplier: 2, jitter: true)
          @base_delay = base_delay
          @max_delay = max_delay
          @multiplier = multiplier
          @jitter = jitter
        end

        # Calculate delay for the given retry attempt
        def delay_for(retry_count)
          delay = [base_delay * (multiplier**retry_count), max_delay].min

          if jitter
            # Add random jitter (±25%) to prevent thundering herd
            jitter_amount = delay * 0.25
            jittered_delay = delay + ((rand * 2 * jitter_amount) - jitter_amount)
            # Ensure we don't exceed max_delay even with jitter
            [jittered_delay, max_delay].min
          else
            delay
          end
        end
      end

      # Linear backoff strategy
      class LinearBackoff
        attr_reader :base_delay, :max_delay, :increment

        def initialize(base_delay: 1, max_delay: 60, increment: 5)
          @base_delay = base_delay
          @max_delay = max_delay
          @increment = increment
        end

        def delay_for(retry_count)
          [base_delay + (increment * retry_count), max_delay].min
        end
      end

      # Fixed delay strategy
      class FixedDelay
        attr_reader :delay

        def initialize(delay: 5)
          @delay = delay
        end

        def delay_for(_retry_count)
          delay
        end
      end

      # Custom retry policy
      class RetryPolicy
        attr_reader :max_retries, :retry_strategy, :retriable_errors, :non_retriable_errors

        def initialize(
          max_retries: 5,
          retry_strategy: ExponentialBackoff.new,
          retriable_errors: nil,
          non_retriable_errors: nil
        )
          @max_retries = max_retries
          @retry_strategy = retry_strategy
          @retriable_errors = Array(retriable_errors) if retriable_errors
          @non_retriable_errors = Array(non_retriable_errors) if non_retriable_errors
        end

        # Check if error is retriable
        def retriable?(error)
          # If non-retriable errors are specified, check those first
          return false if non_retriable_errors&.any? { |klass| error.is_a?(klass) }

          # If retriable errors are specified, only retry those
          if retriable_errors
            # Only retry if the error matches one of the specified retriable errors
            retriable_errors.any? { |klass| error.is_a?(klass) }
          else
            # By default, retry all errors except non-retriable ones
            true
          end
        end

        # Check if we should retry based on count
        def should_retry?(retry_count, error)
          retry_count < max_retries && retriable?(error)
        end

        # Get delay for the current retry
        def retry_delay(retry_count)
          retry_strategy.delay_for(retry_count)
        end
      end

      # Circuit breaker pattern
      class CircuitBreaker
        attr_reader :failure_threshold, :timeout, :half_open_requests

        def initialize(failure_threshold: 5, timeout: 60, half_open_requests: 1)
          @failure_threshold = failure_threshold
          @timeout = timeout
          @half_open_requests = half_open_requests
          @state = :closed
          @failure_count = 0
          @last_failure_time = nil
          @half_open_count = 0
        end

        def call
          case @state
          when :open
            raise CircuitOpenError, "Circuit breaker is open" unless Time.now - @last_failure_time >= timeout

            @state = :half_open
            @half_open_count = 0

          end

          begin
            result = yield
            on_success
            result
          rescue StandardError => e
            on_failure
            raise e
          end
        end

        private

        def on_success
          case @state
          when :half_open
            @half_open_count += 1
            if @half_open_count >= half_open_requests
              @state = :closed
              @failure_count = 0
            end
          when :closed
            @failure_count = 0
          end
        end

        def on_failure
          @failure_count += 1
          @last_failure_time = Time.now

          case @state
          when :closed
            @state = :open if @failure_count >= failure_threshold
          when :half_open
            @state = :open
          end
        end

        class CircuitOpenError < StandardError; end
      end
    end
  end
end
