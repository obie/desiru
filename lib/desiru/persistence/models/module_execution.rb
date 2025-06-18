# frozen_string_literal: true

module Desiru
  module Persistence
    module Models
      # Tracks module execution history
      class ModuleExecution < Base
        set_dataset :module_executions
        many_to_one :api_request

        json_column :inputs
        json_column :outputs
        json_column :metadata

        def validate
          super
          validates_presence %i[module_name status started_at]
          validates_includes %w[pending running completed failed], :status
        end

        def duration
          return nil unless started_at && finished_at

          finished_at - started_at
        end

        def success?
          status == 'completed'
        end

        def failed?
          status == 'failed'
        end
      end
    end
  end
end
