# frozen_string_literal: true

Sequel.migration do
  up do
    # Job Results table for persisting background job results
    create_table(:job_results) do
      primary_key :id
      String :job_id, null: false, unique: true
      String :job_class, null: false
      String :queue, null: false
      String :status, null: false, default: 'pending' # pending, processing, completed, failed
      Integer :progress, default: 0
      String :message
      String :inputs, text: true # JSON
      String :result, text: true # JSON
      String :error_message
      String :error_backtrace, text: true
      Integer :retry_count, default: 0
      DateTime :enqueued_at, null: false
      DateTime :started_at
      DateTime :finished_at
      DateTime :expires_at
      DateTime :created_at, null: false
      DateTime :updated_at, null: false

      index :job_id
      index :job_class
      index :status
      index :queue
      index :created_at
      index :expires_at
      index %i[job_class status]
    end
  end

  down do
    drop_table(:job_results)
  end
end
