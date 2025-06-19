# frozen_string_literal: true

require_relative 'base_repository'

module Desiru
  module Persistence
    module Repositories
      # Repository for module execution records
      class ModuleExecutionRepository < BaseRepository
        def initialize
          super(Models::ModuleExecution)
        end

        def find_by_module(module_name)
          dataset.where(module_name: module_name).all
        end

        def recent(limit = 10)
          dataset
            .order(Sequel.desc(:started_at))
            .limit(limit)
            .all
        end

        def by_status(status)
          dataset.where(status: status).all
        end

        def average_duration(module_name = nil)
          scope = dataset
          scope = scope.where(module_name: module_name) if module_name
          scope = scope.where(status: 'completed')
                       .exclude(finished_at: nil)

          records = scope.all
          return nil if records.empty?

          durations = records.map(&:duration).compact
          return nil if durations.empty?

          durations.sum.to_f / durations.length
        end

        def success_rate(module_name = nil)
          scope = dataset
          scope = scope.where(module_name: module_name) if module_name

          total = scope.count
          return 0.0 if total.zero?

          successful = scope.where(status: 'completed').count
          (successful.to_f / total * 100).round(2)
        end

        def create_for_module(module_name, inputs, api_request_id: nil)
          create(
            module_name: module_name,
            inputs: inputs,
            status: 'pending',
            started_at: Time.now,
            api_request_id: api_request_id
          )
        end

        def complete(id, outputs, metadata = {})
          update(id, {
                   outputs: outputs,
                   metadata: metadata,
                   status: 'completed',
                   finished_at: Time.now
                 })
        end

        def fail(id, error_message, error_backtrace = nil)
          update(id, {
                   error_message: error_message,
                   error_backtrace: error_backtrace,
                   status: 'failed',
                   finished_at: Time.now
                 })
        end
      end
    end
  end
end
