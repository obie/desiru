# frozen_string_literal: true

require 'grape'
require 'json'
require 'rack/cors'

module Desiru
  module API
    # Grape integration for Desiru - automatically generate REST API endpoints from signatures
    class GrapeIntegration
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

      # Generate a Grape API class with all registered modules
      def generate_api
        modules_config = @modules
        async = @async_enabled
        stream = @stream_enabled

        Class.new(Grape::API) do
          format :json
          prefix :api
          version 'v1', using: :path

          # Define class method for type conversion
          def self.grape_type_for(type_string)
            case type_string.to_s.downcase
            when 'integer', 'int'
              Integer
            when 'float'
              Float
            when 'boolean', 'bool'
              Grape::API::Boolean
            when /^list/
              Array
            else
              String # Default to String for unknown types (including 'string', 'str')
            end
          end

          helpers do
            def validate_params(signature, params)
              errors = {}

              signature.input_fields.each do |name, field|
                value = params[name]

                # Check required fields
                if value.nil? && !field.optional?
                  errors[name] = "is required"
                  next
                end

                # Type validation
                next unless value && field.type

                errors[name] = "must be of type #{field.type}" unless validate_type(value, field.type)
              end

              errors
            end

            def validate_type(value, expected_type)
              case expected_type.to_s.downcase
              when 'string', 'str'
                value.is_a?(String)
              when 'integer', 'int'
                value.is_a?(Integer) || (value.is_a?(String) && value.match?(/^\d+$/))
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

            def format_response(result)
              if result.is_a?(Hash)
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
          end

          # Health check endpoint
          desc 'Health check'
          get '/health' do
            { status: 'ok', timestamp: Time.now.iso8601 }
          end

          # Generate endpoints for each registered module
          modules_config.each do |path, config|
            desiru_module = config[:module]
            description = config[:description]

            desc description
            params do
              # Generate params from signature
              desiru_module.signature.input_fields.each do |name, field|
                # Convert Desiru types to Grape types
                grape_type = case field.type.to_s.downcase
                             when 'integer', 'int'
                               Integer
                             when 'float'
                               Float
                             when 'boolean', 'bool'
                               Grape::API::Boolean
                             when /^list/
                               Array
                             else
                               String # Default to String for unknown types (including 'string', 'str')
                             end

                optional name, type: grape_type, desc: field.description
              end
            end

            post path do
              # Validate parameters
              validation_errors = validate_params(desiru_module.signature, params)

              error!({ errors: validation_errors }, 422) if validation_errors.any?

              # Prepare inputs with symbolized keys
              inputs = {}
              desiru_module.signature.input_fields.each_key do |key|
                value = params[key.to_s] || params[key.to_sym]
                inputs[key] = value if value
              end

              begin
                if async && params[:async] == true && desiru_module.respond_to?(:call_async)
                  # Handle async request
                  status 202
                  handle_async_request(desiru_module, inputs)
                elsif params[:async] == true
                  # Module doesn't support async
                  error!({ error: 'This module does not support async execution' }, 400)
                else
                  # Synchronous execution
                  result = desiru_module.call(inputs)
                  status 201
                  format_response(result)
                end
              rescue StandardError => e
                error!({ error: e.message }, 500)
              end
            end
          end

          # Job status endpoint if async is enabled
          if async
            namespace :jobs do
              desc 'Get job status'
              params do
                requires :id, type: String, desc: 'Job ID'
              end
              get ':id' do
                status = Desiru::AsyncStatus.new(params[:id])

                response = {
                  job_id: params[:id],
                  status: status.status,
                  progress: status.progress
                }

                response[:result] = status.result if status.ready?

                response
              rescue StandardError
                error!({ error: "Job not found" }, 404)
              end
            end
          end

          # Add streaming endpoint support if enabled
          if stream
            namespace :stream do
              modules_config.each do |path, config|
                desiru_module = config[:module]
                description = "#{config[:description]} (streaming)"

                desc description
                params do
                  desiru_module.signature.input_fields.each do |name, field|
                    # Convert Desiru types to Grape types
                    grape_type = case field.type.to_s.downcase
                                 when 'integer', 'int'
                                   Integer
                                 when 'float'
                                   Float
                                 when 'boolean', 'bool'
                                   Grape::API::Boolean
                                 when /^list/
                                   Array
                                 else
                                   String # Default to String for unknown types (including 'string', 'str')
                                 end

                    optional name, type: grape_type, desc: field.description
                  end
                end

                post path do
                  content_type 'text/event-stream'
                  headers['Cache-Control'] = 'no-cache'
                  headers['X-Accel-Buffering'] = 'no'
                  status 200

                  stream do |out|
                    inputs = {}
                    desiru_module.signature.input_fields.each_key do |key|
                      inputs[key] = params[key.to_s] if params.key?(key.to_s)
                    end

                    # For now, just send the result as a single event
                    # Future: integrate with actual streaming from LLM
                    result = desiru_module.call(inputs)

                    out << "event: result\n"
                    out << "data: #{JSON.generate(format_response(result))}\n\n"

                    out << "event: done\n"
                    out << "data: {\"status\": \"complete\"}\n\n"
                  rescue StandardError => e
                    out << "event: error\n"
                    out << "data: #{JSON.generate({ error: e.message })}\n\n"
                  end
                end
              end
            end
          end
        end
      end

      # Mount the API in a Rack application
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
