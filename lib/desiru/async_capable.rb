# frozen_string_literal: true

require 'securerandom'
require 'redis'
require 'json'

module Desiru
  module AsyncCapable
    def call_async(inputs = {})
      job_id = SecureRandom.uuid

      Desiru::Jobs::AsyncPredict.perform_async(
        job_id,
        self.class.name,
        signature.to_s,
        inputs,
        {
          'model_class' => model.class.name,
          'model_config' => model_config,
          'config' => config,
          'demos' => demos
        }
      )

      AsyncResult.new(job_id)
    end

    def call_batch_async(inputs_array)
      batch_id = SecureRandom.uuid

      Desiru::Jobs::BatchProcessor.perform_async(
        batch_id,
        self.class.name,
        signature.to_s,
        inputs_array,
        {
          'model_class' => model.class.name,
          'model_config' => model_config,
          'config' => config,
          'demos' => demos
        }
      )

      BatchResult.new(batch_id)
    end

    private

    def model_config
      return {} unless model.respond_to?(:to_config)

      model.to_config
    end
  end

  class AsyncResult
    attr_reader :job_id

    def initialize(job_id)
      @job_id = job_id
      @redis = Redis.new(url: Desiru.configuration.redis_url || ENV.fetch('REDIS_URL', nil))
    end

    def ready?
      result = fetch_result
      !result.nil?
    end

    def success?
      result = fetch_result
      result && result[:success]
    end

    def failed?
      result = fetch_result
      result && !result[:success]
    end

    def result
      data = fetch_result
      return nil unless data

      raise ModuleError, "Async job failed: #{data[:error]}" unless data[:success]

      ModuleResult.new(data[:result], metadata: { async: true, job_id: job_id })
    end

    def error
      data = fetch_result
      return nil unless data && !data[:success]

      {
        message: data[:error],
        class: data[:error_class]
      }
    end

    def status
      status_data = fetch_status
      return 'pending' unless status_data

      status_data[:status] || 'pending'
    end

    def progress
      status_data = fetch_status
      return nil unless status_data

      status_data[:progress]
    end

    def wait(timeout: 60, poll_interval: 0.5)
      start_time = Time.now

      while Time.now - start_time < timeout
        return result if ready?

        sleep poll_interval
      end

      raise TimeoutError, "Async result not ready after #{timeout} seconds"
    end

    private

    def fetch_result
      raw = @redis.get("desiru:results:#{job_id}")
      return nil unless raw

      JSON.parse(raw, symbolize_names: true)
    end

    def fetch_status
      raw = @redis.get("desiru:status:#{job_id}")
      return nil unless raw

      JSON.parse(raw, symbolize_names: true)
    end
  end

  class BatchResult < AsyncResult
    def results
      data = fetch_result
      return [] unless data && data[:results]

      data[:results].map do |item|
        ModuleResult.new(item[:result], metadata: { batch_index: item[:index] }) if item[:success]
      end
    end

    def errors
      data = fetch_result
      return [] unless data && data[:errors]

      data[:errors]
    end

    def stats
      data = fetch_result
      return {} unless data

      {
        total: data[:total],
        successful: data[:successful],
        failed: data[:failed],
        success_rate: data[:total].positive? ? data[:successful].to_f / data[:total] : 0
      }
    end
  end
end
