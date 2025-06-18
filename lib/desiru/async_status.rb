# frozen_string_literal: true

require 'redis'
require 'json'

module Desiru
  # AsyncStatus provides a simple interface for checking job status
  # Compatible with the REST API's job status endpoint
  class AsyncStatus
    attr_reader :job_id

    def initialize(job_id)
      @job_id = job_id
      @redis = Redis.new(url: Desiru.configuration.redis_url || ENV.fetch('REDIS_URL', nil))
    end

    def status
      status_data = fetch_status
      return 'pending' unless status_data

      status_data[:status] || 'pending'
    end

    def progress
      status_data = fetch_status
      return 0 unless status_data

      status_data[:progress] || 0
    end

    def ready?
      result_data = fetch_result
      !result_data.nil?
    end

    def result
      result_data = fetch_result
      return nil unless result_data

      raise ModuleError, "Async job failed: #{result_data[:error]}" unless result_data[:success]

      result_data[:result]
    end

    private

    def fetch_status
      raw = @redis.get("desiru:status:#{job_id}")
      return nil unless raw

      JSON.parse(raw, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end

    def fetch_result
      raw = @redis.get("desiru:results:#{job_id}")
      return nil unless raw

      JSON.parse(raw, symbolize_names: true)
    rescue JSON::ParserError
      nil
    end
  end
end
