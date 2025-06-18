# frozen_string_literal: true

module Desiru
  module Persistence
    module Models
      # Tracks REST API requests
      class ApiRequest < Base
        one_to_many :module_executions

        json_column :headers
        json_column :params
        json_column :response_body

        def validate
          super
          # Validate method column separately due to name conflict with Ruby's method method
          if self[:method].nil? || self[:method].to_s.empty?
            errors.add(:method, 'is required')
          elsif !%w[GET POST PUT PATCH DELETE].include?(self[:method])
            errors.add(:method, 'must be GET, POST, PUT, PATCH, or DELETE')
          end
          validates_presence %i[path status_code]
        end

        def success?
          status_code >= 200 && status_code < 300
        end

        def duration_ms
          return nil unless response_time

          (response_time * 1000).round
        end
      end
    end
  end
end
