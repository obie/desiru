# frozen_string_literal: true

require 'sidekiq'
require 'redis'
require 'json'

module Desiru
  module Jobs
    class Base
      include Sidekiq::Job

      sidekiq_options retry: 3, dead: true

      def perform(*)
        raise NotImplementedError, "#{self.class} must implement #perform"
      end

      protected

      def store_result(job_id, result, ttl: 3600)
        # Store in Redis for fast access
        redis.setex(result_key(job_id), ttl, result.to_json)

        # Also persist to database for long-term storage
        persist_result_to_db(job_id, result)
      end

      def fetch_result(job_id)
        result = redis.get(result_key(job_id))
        result ? JSON.parse(result, symbolize_names: true) : nil
      end

      def result_key(job_id)
        "desiru:results:#{job_id}"
      end

      def redis
        @redis ||= Redis.new(url: Desiru.configuration.redis_url || ENV.fetch('REDIS_URL', nil))
      end

      def update_status(job_id, status, progress: nil, message: nil)
        status_data = {
          status: status,
          updated_at: Time.now.iso8601
        }
        status_data[:progress] = progress if progress
        status_data[:message] = message if message

        redis.setex(status_key(job_id), 86_400, status_data.to_json)

        # Also persist to database
        persist_status_to_db(job_id, status, progress: progress, message: message)
      end

      def status_key(job_id)
        "desiru:status:#{job_id}"
      end

      # Database persistence methods
      def persist_result_to_db(job_id, result)
        return unless persistence_enabled?

        job_repo.mark_completed(job_id, result)
      rescue StandardError => e
        Desiru.logger.warn("Failed to persist job result to database: #{e.message}")
      end

      def persist_error_to_db(job_id, error, backtrace = nil)
        return unless persistence_enabled?

        job_repo.mark_failed(job_id, error, backtrace: backtrace)
      rescue StandardError => e
        Desiru.logger.warn("Failed to persist job error to database: #{e.message}")
      end

      def persist_status_to_db(job_id, status, progress: nil, message: nil)
        return unless persistence_enabled?

        case status
        when 'processing'
          job_repo.mark_processing(job_id)
          # Also update progress if provided
          job_repo.update_progress(job_id, progress, message: message) if progress
        when 'completed'
          # Already handled by persist_result_to_db
        when 'failed'
          # Already handled by persist_error_to_db
        else
          job_repo.update_progress(job_id, progress, message: message) if progress
        end
      rescue StandardError => e
        Desiru.logger.warn("Failed to persist job status to database: #{e.message}")
      end

      def create_job_record(job_id, inputs: nil, expires_at: nil)
        return unless persistence_enabled?

        job_repo.create_for_job(
          job_id,
          self.class.name,
          self.class.get_sidekiq_options['queue'] || 'default',
          inputs: inputs,
          expires_at: expires_at
        )
      rescue StandardError => e
        Desiru.logger.warn("Failed to create job record in database: #{e.message}")
      end

      def persistence_enabled?
        Desiru::Persistence.enabled?
      rescue StandardError
        false
      end

      def job_repo
        @job_repo ||= Desiru::Persistence.repositories[:job_results]
      end
    end
  end
end
