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
        redis.setex(result_key(job_id), ttl, result.to_json)
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
      end

      def status_key(job_id)
        "desiru:status:#{job_id}"
      end
    end
  end
end
