# frozen_string_literal: true

require_relative 'base_repository'

module Desiru
  module Persistence
    module Repositories
      # Repository for API request records
      class ApiRequestRepository < BaseRepository
        def initialize
          super(Models::ApiRequest)
        end

        def find_by_path(path)
          dataset.where(path: path).all
        end

        def recent(limit = 10)
          dataset
            .order(Sequel.desc(:created_at))
            .limit(limit)
            .all
        end

        def by_status_code_range(min, max)
          dataset.where(status_code: min..max).all
        end

        def successful
          by_status_code_range(200, 299)
        end

        def failed
          dataset.where { status_code >= 400 }.all
        end

        def average_response_time(path = nil)
          scope = dataset
          scope = scope.where(path: path) if path
          scope = scope.exclude(response_time: nil)

          avg = scope.avg(:response_time)
          avg ? avg.round(3) : nil
        end

        def requests_per_minute(minutes_ago = 60)
          since = Time.now - (minutes_ago * 60)
          count = dataset.where { created_at >= since }.count

          (count.to_f / minutes_ago).round(2)
        end

        def top_paths(limit = 10)
          dataset
            .group_and_count(:path)
            .order(Sequel.desc(:count))
            .limit(limit)
            .map { |row| { path: row[:path], count: row[:count] } }
        end

        def create_from_rack_request(request, response)
          create(
            method: request.request_method,
            path: request.path_info,
            remote_ip: request.ip,
            headers: extract_headers(request),
            params: request.params,
            status_code: response.status,
            response_body: extract_response_body(response),
            response_time: response.headers['X-Runtime']&.to_f
          )
        end

        private

        def extract_headers(request)
          headers = {}
          request.each_header do |key, value|
            next unless key.start_with?('HTTP_')

            header_name = key.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-')
            headers[header_name] = value
          end
          headers
        end

        def extract_response_body(response)
          return nil unless response.body.respond_to?(:each)

          body = []
          response.body.each { |part| body << part }
          body.join
        rescue StandardError
          nil
        end
      end
    end
  end
end
