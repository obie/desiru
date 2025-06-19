# frozen_string_literal: true

module Desiru
  module Persistence
    module Models
      # Stores training examples for modules
      class TrainingExample < Base
        set_dataset :training_examples
        json_column :inputs
        json_column :expected_outputs
        json_column :metadata

        def validate
          super
          validates_presence %i[module_name inputs]
          validates_includes %w[training validation test], :dataset_type if dataset_type
        end

        def used?
          used_count&.positive?
        end
      end
    end
  end
end
