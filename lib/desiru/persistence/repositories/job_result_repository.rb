# frozen_string_literal: true

require_relative 'base_repository'

module Desiru
  module Persistence
    module Repositories
      # Repository for job result persistence
      class JobResultRepository < BaseRepository
        def initialize
          super(Models::JobResult)
        end

        def create_for_job(job_id, job_class, queue, inputs: nil, expires_at: nil)
          create(
            job_id: job_id,
            job_class: job_class,
            queue: queue,
            status: Models::JobResult::STATUS_PENDING,
            inputs: inputs&.to_json,
            enqueued_at: Time.now,
            expires_at: expires_at
          )
        end

        def find_by_job_id(job_id)
          find_by(job_id: job_id)
        end

        def mark_processing(job_id)
          job_result = find_by_job_id(job_id)
          return nil unless job_result

          job_result.mark_as_processing!
          job_result
        end

        def mark_completed(job_id, result, message: nil)
          job_result = find_by_job_id(job_id)
          return nil unless job_result

          job_result.mark_as_completed!(result, message: message)
          job_result
        end

        def mark_failed(job_id, error, backtrace: nil, increment_retry: true)
          job_result = find_by_job_id(job_id)
          return nil unless job_result

          updates = {
            status: Models::JobResult::STATUS_FAILED,
            finished_at: Time.now,
            error_message: error.to_s,
            error_backtrace: backtrace&.join("\n")
          }

          updates[:retry_count] = job_result.retry_count + 1 if increment_retry

          job_result.update(updates)
          job_result
        end

        def update_progress(job_id, progress, message: nil)
          job_result = find_by_job_id(job_id)
          return nil unless job_result

          job_result.update_progress(progress, message: message)
          job_result
        end

        def cleanup_expired
          dataset.expired.delete
        end

        def recent_by_class(job_class, limit: 10)
          dataset.by_job_class(job_class).recent(limit).all
        end

        def statistics(job_class: nil, since: nil)
          scope = dataset
          scope = scope.by_job_class(job_class) if job_class
          scope = scope.where { created_at >= since } if since

          {
            total: scope.count,
            pending: scope.pending.count,
            processing: scope.processing.count,
            completed: scope.completed.count,
            failed: scope.failed.count,
            average_duration: calculate_average_duration(scope)
          }
        end

        private

        def calculate_average_duration(dataset)
          completed = dataset.completed.where(Sequel.~(started_at: nil)).where(Sequel.~(finished_at: nil))
          return 0 if completed.empty?

          total_duration = 0
          count = 0

          completed.each do |job|
            next unless job.started_at && job.finished_at

            duration = job.finished_at - job.started_at
            total_duration += duration
            count += 1
          end

          count > 0 ? total_duration / count : 0
        end
      end
    end
  end
end
