# frozen_string_literal: true

require 'sinatra/base'
require 'sinatra/json'
require 'json'
require 'rack/cors'

module Desiru
  module API
    # Sinatra integration for Desiru - lightweight REST API generation
    class SinatraIntegration
      attr_reader :modules, :async_enabled, :stream_enabled

      def initialize(async_enabled: true, stream_enabled: false)
        @modules = {}
        @async_enabled = async_enabled
        @stream_enabled = stream_enabled
      end

      # Register a Desiru module with an endpoint path
      def register_module(path, desiru_module, description: nil)
        @modules[path] = {
          module: desiru_module,
          description: description || "Endpoint for #{desiru_module.class.name}"
        }
      end

      # Generate a Sinatra application with all registered modules
      def generate_api
        modules_config = @modules
        async = @async_enabled
        stream = @stream_enabled

        Class.new(Sinatra::Base) do
          set :show_exceptions, false
          set :raise_errors, true

          # Helpers for parameter validation and response formatting
          helpers do
            def validate_type(value, type_string)
              case type_string.to_s.downcase
              when 'string', 'str'
                value.is_a?(String)
              when 'integer', 'int'
                value.is_a?(Integer) || (value.is_a?(String) && value.match?(/\A-?\d+\z/))
              when 'float'
                value.is_a?(Numeric)
              when 'boolean', 'bool'
                [true, false, 'true', 'false'].include?(value)
              when /^list/
                value.is_a?(Array)
              else
                true # Unknown types and literals pass validation
              end
            end

            def coerce_value(value, type_string)
              case type_string.to_s.downcase
              when 'integer', 'int'
                value.to_i
              when 'float'
                value.to_f
              when 'boolean', 'bool'
                ['true', true].include?(value)
              else
                value
              end
            end

            def format_response(result)
              if result.is_a?(Desiru::ModuleResult)
                result.data
              elsif result.is_a?(Hash)
                result
              else
                { result: result }
              end
            end

            def handle_async_request(desiru_module, inputs)
              result = desiru_module.call_async(inputs)

              {
                job_id: result.job_id,
                status: result.status,
                progress: result.progress,
                status_url: "/api/v1/jobs/#{result.job_id}"
              }
            end

            def parse_json_body
              request.body.rewind
              JSON.parse(request.body.read)
            rescue JSON::ParserError
              halt 400, json(error: 'Invalid JSON')
            end
          end

          # Content type handling
          before do
            content_type :json
          end

          # Health check endpoint
          get '/api/v1/health' do
            json status: 'ok', timestamp: Time.now.iso8601
          end

          # Generate endpoints for each registered module
          modules_config.each do |path, config|
            desiru_module = config[:module]

            # Main module endpoint
            post "/api/v1#{path}" do
              params = parse_json_body

              # Convert string keys to symbols for module call
              symbolized_params = {}
              params.each { |k, v| symbolized_params[k.to_sym] = v }

              begin
                result = desiru_module.call(symbolized_params)
                json format_response(result)
              rescue Desiru::ModuleError => e
                halt 400, json(error: e.message)
              rescue StandardError => e
                halt 500, json(error: e.message)
              end
            end

            # Async endpoint
            if async && desiru_module.respond_to?(:call_async)
              post "/api/v1/async#{path}" do
                params = parse_json_body

                begin
                  result = handle_async_request(desiru_module, params)
                  status 202
                  json result
                rescue StandardError => e
                  halt 500, json(error: e.message)
                end
              end
            end

            # Streaming endpoint (Server-Sent Events)
            next unless stream && desiru_module.respond_to?(:call_stream)

            post "/api/v1/stream#{path}" do
              content_type 'text/event-stream'
              stream do |out|
                params = parse_json_body

                begin
                  desiru_module.call_stream(params) do |chunk|
                    out << "event: chunk\n"
                    out << "data: #{JSON.generate(chunk)}\n\n"
                  end

                  # Send final result
                  result = desiru_module.call(params)
                  out << "event: result\n"
                  out << "data: #{JSON.generate(format_response(result))}\n\n"
                  out << "event: done\n"
                  out << "data: #{JSON.generate({ status: 'complete' })}\n\n"
                rescue StandardError => e
                  out << "event: error\n"
                  out << "data: #{JSON.generate(error: e.message)}\n\n"
                ensure
                  out.close
                end
              end
            end
          end

          # Job status endpoint for async requests
          if async
            get '/api/v1/jobs/:job_id' do
              job_id = params[:job_id]

              if Desiru.respond_to?(:check_job_status)
                status = Desiru.check_job_status(job_id)

                if status
                  json status
                else
                  halt 404, json(error: 'Job not found')
                end
              else
                halt 501, json(error: 'Async job tracking not implemented')
              end
            end
          end
        end
      end

      # Mount the API in a Rack application with CORS
      def to_rack_app
        api = generate_api

        Rack::Builder.new do
          use Rack::Cors do
            allow do
              origins '*'
              resource '*',
                       headers: :any,
                       methods: %i[get post put patch delete options head],
                       expose: ['Access-Control-Allow-Origin']
            end
          end

          run api
        end
      end
    end
  end
end
