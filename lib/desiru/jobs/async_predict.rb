# frozen_string_literal: true

require_relative 'base'

module Desiru
  module Jobs
    class AsyncPredict < Base
      sidekiq_options queue: 'critical'

      def perform(job_id, module_class_name, signature_str, inputs, options = {})
        update_status(job_id, 'running', message: 'Initializing module')

        module_class = Object.const_get(module_class_name)

        # Extract module initialization parameters
        model_class = options.delete('model_class')
        model_config = options.delete('model_config') || {}
        config = options.delete('config') || {}
        demos = options.delete('demos') || []

        # Initialize model if provided
        model = (Object.const_get(model_class).new(**model_config) if model_class && model_config)

        module_instance = module_class.new(
          signature_str,
          model: model,
          config: config,
          demos: demos
        )

        update_status(job_id, 'running', progress: 50, message: 'Processing request')
        result = module_instance.call(**inputs)

        update_status(job_id, 'completed', progress: 100, message: 'Request completed successfully')
        store_result(job_id, {
                       success: true,
                       result: result.to_h,
                       completed_at: Time.now.iso8601
                     })
      rescue StandardError => e
        update_status(job_id, 'failed', message: "Error: #{e.message}")
        store_result(job_id, {
                       success: false,
                       error: e.message,
                       error_class: e.class.name,
                       completed_at: Time.now.iso8601
                     })
        raise
      end
    end
  end
end
