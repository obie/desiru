# frozen_string_literal: true

require_relative 'base_repository'

module Desiru
  module Persistence
    module Repositories
      # Repository for optimization result records
      class OptimizationResultRepository < BaseRepository
        def initialize
          super(Models::OptimizationResult)
        end

        def find_by_module(module_name)
          dataset.where(module_name: module_name).all
        end

        def find_best_for_module(module_name)
          dataset
            .where(module_name: module_name)
            .order(Sequel.desc(:score))
            .first
        end

        def recent(limit = 10)
          dataset
            .order(Sequel.desc(:created_at))
            .limit(limit)
            .all
        end

        def by_optimizer_type(type)
          dataset.where(optimizer_type: type).all
        end

        def average_improvement(module_name = nil)
          scope = dataset.exclude(baseline_score: nil)
          scope = scope.where(module_name: module_name) if module_name

          improvements = scope.select_map do |record|
            record.improvement_percentage
          end.compact

          return nil if improvements.empty?

          improvements.sum / improvements.length
        end

        def top_performers(limit = 5)
          dataset
            .exclude(baseline_score: nil)
            .order(Sequel.desc { (score - baseline_score) / baseline_score })
            .limit(limit)
            .all
        end

        def create_result(module_name:, optimizer_type:, score:, **attributes)
          create(
            module_name: module_name,
            optimizer_type: optimizer_type,
            score: score,
            started_at: attributes[:started_at] || Time.now,
            **attributes
          )
        end
      end
    end
  end
end
