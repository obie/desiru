# frozen_string_literal: true

Sequel.migration do
  up do
    # API Requests table
    create_table(:api_requests) do
      primary_key :id
      String :method, null: false
      String :path, null: false
      String :remote_ip
      Integer :status_code, null: false
      Float :response_time
      String :headers, text: true # JSON
      String :params, text: true # JSON
      String :response_body, text: true # JSON
      String :error_message
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :path
      index :status_code
      index :created_at
    end

    # Module Executions table
    create_table(:module_executions) do
      primary_key :id
      foreign_key :api_request_id, :api_requests, on_delete: :cascade
      String :module_name, null: false
      String :module_type
      String :status, null: false, default: 'pending'
      String :inputs, text: true # JSON
      String :outputs, text: true # JSON
      String :metadata, text: true # JSON
      String :error_message
      String :error_backtrace, text: true
      DateTime :started_at, null: false
      DateTime :finished_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :module_name
      index :status
      index :started_at
      index %i[module_name status]
    end

    # Optimization Results table
    create_table(:optimization_results) do
      primary_key :id
      String :module_name, null: false
      String :optimizer_type, null: false
      Float :score, null: false
      Float :baseline_score
      Integer :training_size
      Integer :validation_size
      String :parameters, text: true # JSON
      String :metrics, text: true # JSON
      String :best_prompts, text: true # JSON
      DateTime :started_at
      DateTime :finished_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :module_name
      index :optimizer_type
      index :score
      index %i[module_name optimizer_type]
    end

    # Training Examples table
    create_table(:training_examples) do
      primary_key :id
      String :module_name, null: false
      String :dataset_type, default: 'training'
      String :inputs, text: true, null: false # JSON
      String :expected_outputs, text: true # JSON
      String :metadata, text: true # JSON
      Integer :used_count, default: 0
      DateTime :last_used_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :module_name
      index :dataset_type
      index %i[module_name dataset_type]
    end
  end

  down do
    drop_table(:training_examples)
    drop_table(:optimization_results)
    drop_table(:module_executions)
    drop_table(:api_requests)
  end
end
