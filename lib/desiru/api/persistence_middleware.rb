# frozen_string_literal: true

require 'rack'

module Desiru
  module API
    # Rack middleware for tracking API requests and module executions
    class PersistenceMiddleware
      def initialize(app, enabled: true)
        @app = app
        @enabled = enabled
      end

      def call(env)
        return @app.call(env) unless @enabled && persistence_available?

        start_time = Time.now

        # Create request record
        request = Rack::Request.new(env)

        # Call the app
        status, headers, body = @app.call(env)

        # Calculate response time
        response_time = Time.now - start_time

        # Store the request and response
        store_request(request, status, headers, body, response_time)

        # Return the response
        [status, headers, body]
      rescue StandardError => e
        # Log error but don't fail the request
        warn "PersistenceMiddleware error: #{e.message}"
        [status, headers, body] || [500, {}, ['Internal Server Error']]
      end

      private

      def persistence_available?
        defined?(Desiru::Persistence) &&
          Desiru::Persistence::Database.connection &&
          Desiru::Persistence::Setup.initialized?
      rescue StandardError
        false
      end

      def store_request(request, status, _headers, body, response_time)
        # Only track API endpoints
        return unless request.path_info.start_with?('/api/')

        api_requests = Desiru::Persistence[:api_requests]

        api_request = api_requests.create(
          method: request.request_method,
          path: request.path_info,
          remote_ip: request.ip,
          headers: extract_headers(request),
          params: extract_params(request),
          status_code: status,
          response_body: extract_body(body),
          response_time: response_time
        )

        # Store module execution if available
        store_module_execution(api_request.id, request, body) if api_request
      rescue StandardError => e
        warn "Failed to store request: #{e.message}"
      end

      def extract_headers(request)
        headers = {}
        request.each_header do |key, value|
          next unless key.start_with?('HTTP_') || key == 'CONTENT_TYPE'

          header_name = key.sub(/^HTTP_/, '').split('_').map(&:capitalize).join('-')
          headers[header_name] = value
        end
        headers
      end

      def extract_params(request)
        if request.content_type&.include?('application/json')
          request.body.rewind
          JSON.parse(request.body.read)
        else
          request.params
        end
      rescue StandardError
        request.params
      end

      def extract_body(body)
        return nil unless body.respond_to?(:each)

        content = body.map { |part| part }

        # Try to parse as JSON
        JSON.parse(content.join)
      rescue StandardError
        content.join
      end

      def store_module_execution(api_request_id, request, body)
        # Extract module info from path (e.g., /api/v1/summarize -> summarize)
        module_path = request.path_info.gsub(%r{^/api/v\d+/}, '')
        return unless module_path && !module_path.empty?

        params = extract_params(request)
        result = extract_body(body)

        module_executions = Desiru::Persistence[:module_executions]

        execution = module_executions.create_for_module(
          module_path.capitalize,
          params,
          api_request_id: api_request_id
        )

        # Mark as completed if we have a result
        if result.is_a?(Hash) && !result['error']
          module_executions.complete(execution.id, result)
        elsif result.is_a?(Hash) && result['error']
          module_executions.fail(execution.id, result['error'])
        end
      rescue StandardError => e
        warn "Failed to store module execution: #{e.message}"
      end
    end

    # Extension for API integrations to add persistence
    module PersistenceExtension
      def with_persistence(enabled: true)
        original_app = to_rack_app

        Rack::Builder.new do
          use PersistenceMiddleware, enabled: enabled
          run original_app
        end
      end
    end
  end
end

# Add extension to API integrations
Desiru::API::GrapeIntegration.include(Desiru::API::PersistenceExtension) if defined?(Desiru::API::GrapeIntegration)
Desiru::API::SinatraIntegration.include(Desiru::API::PersistenceExtension) if defined?(Desiru::API::SinatraIntegration)
