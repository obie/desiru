# frozen_string_literal: true

require_relative 'base'

module Desiru
  module Jobs
    class BatchProcessor < Base
      sidekiq_options queue: 'default'

      def perform(batch_id, module_class_name, signature_str, inputs_array, options = {})
        total_items = inputs_array.size
        update_status(batch_id, 'running', progress: 0, message: "Processing #{total_items} items")

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

        results = []
        errors = []

        inputs_array.each_with_index do |inputs, index|
          progress = ((index + 1).to_f / total_items * 100).round
          update_status(batch_id, 'running', progress: progress,
                                             message: "Processing item #{index + 1} of #{total_items}")

          result = module_instance.call(**inputs)
          results << {
            index: index,
            success: true,
            result: result.to_h
          }
        rescue StandardError => e
          errors << {
            index: index,
            success: false,
            error: e.message,
            error_class: e.class.name
          }
        end

        final_status = errors.empty? ? 'completed' : 'completed_with_errors'
        update_status(batch_id, final_status, progress: 100,
                                              message: "Processed #{results.size} successfully, #{errors.size} failed")

        store_result(batch_id, {
                       success: errors.empty?,
                       total: inputs_array.size,
                       successful: results.size,
                       failed: errors.size,
                       results: results,
                       errors: errors,
                       completed_at: Time.now.iso8601
                     }, ttl: 7200) # 2 hours TTL for batch results
      end
    end
  end
end
