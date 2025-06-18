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
          validates_presence %i[method path status_code]
          validates_includes %w[GET POST PUT PATCH DELETE], :method
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
