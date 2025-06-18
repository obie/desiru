# frozen_string_literal: true

module Desiru
  module Persistence
    module Models
      # Stores optimization results and metrics
      class OptimizationResult < Base
        json_column :parameters
        json_column :metrics
        json_column :best_prompts

        def validate
          super
          validates_presence %i[module_name optimizer_type score]
          validates_numeric :score
          validates_min_length 1, :training_size if training_size
        end

        def improvement_percentage
          return nil unless baseline_score && score > 0

          ((score - baseline_score) / baseline_score * 100).round(2)
        end
      end
    end
  end
end
