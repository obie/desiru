# frozen_string_literal: true

require_relative 'base_repository'

module Desiru
  module Persistence
    module Repositories
      # Repository for training example records
      class TrainingExampleRepository < BaseRepository
        def initialize
          super(Models::TrainingExample)
        end

        def find_by_module(module_name, dataset_type: nil)
          scope = dataset.where(module_name: module_name)
          scope = scope.where(dataset_type: dataset_type) if dataset_type
          scope.all
        end

        def find_unused(module_name, limit = 10)
          dataset
            .where(module_name: module_name, used_count: 0)
            .limit(limit)
            .all
        end

        def find_least_used(module_name, limit = 10)
          dataset
            .where(module_name: module_name)
            .order(:used_count, :last_used_at)
            .limit(limit)
            .all
        end

        def mark_as_used(id)
          record = find(id)
          return false unless record

          record.update(
            used_count: record.used_count + 1,
            last_used_at: Time.now
          )
          true
        end

        def bulk_create(module_name, examples, dataset_type: 'training')
          transaction do
            examples.map do |example|
              create(
                module_name: module_name,
                dataset_type: dataset_type,
                inputs: example[:inputs],
                expected_outputs: example[:outputs],
                metadata: example[:metadata]
              )
            end
          end
        end

        def split_dataset(module_name, train_ratio: 0.8, val_ratio: 0.1)
          all_examples = find_by_module(module_name)
          total = all_examples.length

          train_size = (total * train_ratio).floor
          val_size = (total * val_ratio).floor

          shuffled = all_examples.shuffle

          {
            training: shuffled[0...train_size],
            validation: shuffled[train_size...(train_size + val_size)],
            test: shuffled[(train_size + val_size)..]
          }
        end

        def export_for_training(module_name, format: :dspy)
          examples = find_by_module(module_name, dataset_type: 'training')

          case format
          when :dspy
            examples.map do |ex|
              {
                inputs: ex.inputs,
                outputs: ex.expected_outputs
              }
            end
          when :jsonl
            examples.map do |ex|
              JSON.generate({
                              inputs: ex.inputs,
                              outputs: ex.expected_outputs,
                              metadata: ex.metadata
                            })
            end.join("\n")
          else
            raise ArgumentError, "Unknown format: #{format}"
          end
        end
      end
    end
  end
end
