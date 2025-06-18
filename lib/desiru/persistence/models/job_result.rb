# frozen_string_literal: true

module Desiru
  module Persistence
    module Models
      # Model for storing background job results
      class JobResult < Sequel::Model(:job_results)
        plugin :timestamps, update_on_create: true
        plugin :json_serializer
        plugin :validation_helpers

        # Status constants
        STATUS_PENDING = 'pending'
        STATUS_PROCESSING = 'processing'
        STATUS_COMPLETED = 'completed'
        STATUS_FAILED = 'failed'

        # Validations
        def validate
          super
          validates_presence %i[job_id job_class queue status enqueued_at]
          validates_unique :job_id
          validates_includes %w[pending processing completed failed], :status
        end

        # Scopes
        dataset_module do
          def pending
            where(status: STATUS_PENDING)
          end

          def processing
            where(status: STATUS_PROCESSING)
          end

          def completed
            where(status: STATUS_COMPLETED)
          end

          def failed
            where(status: STATUS_FAILED)
          end

          def expired
            where { expires_at < Time.now }
          end

          def active
            where { (expires_at > Time.now) | (expires_at =~ nil) }
          end

          def by_job_class(job_class)
            where(job_class: job_class)
          end

          def recent(limit = 10)
            order(Sequel.desc(:created_at)).limit(limit)
          end
        end

        # Instance methods
        def pending?
          status == STATUS_PENDING
        end

        def processing?
          status == STATUS_PROCESSING
        end

        def completed?
          status == STATUS_COMPLETED
        end

        def failed?
          status == STATUS_FAILED
        end

        def expired?
          expires_at && expires_at < Time.now
        end

        def duration
          return nil unless started_at && finished_at

          finished_at - started_at
        end

        # JSON field accessors
        def inputs_data
          return {} unless inputs

          JSON.parse(inputs, symbolize_names: true)
        rescue JSON::ParserError
          {}
        end

        def result_data
          return {} unless result

          JSON.parse(result, symbolize_names: true)
        rescue JSON::ParserError
          {}
        end

        def mark_as_processing!
          update(
            status: STATUS_PROCESSING,
            started_at: Time.now,
            progress: 0
          )
        end

        def mark_as_completed!(result_data, message: nil)
          update(
            status: STATUS_COMPLETED,
            finished_at: Time.now,
            progress: 100,
            result: result_data.to_json,
            message: message
          )
        end

        def mark_as_failed!(error, backtrace: nil)
          update(
            status: STATUS_FAILED,
            finished_at: Time.now,
            error_message: error.to_s,
            error_backtrace: backtrace&.join("\n")
          )
        end

        def update_progress(progress, message: nil)
          updates = { progress: progress }
          updates[:message] = message if message
          update(updates)
        end
      end
    end
  end
end
