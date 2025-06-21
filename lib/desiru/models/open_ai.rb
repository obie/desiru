# frozen_string_literal: true

require 'openai'

module Desiru
  module Models
    # OpenAI GPT model adapter
    class OpenAI < Base
      DEFAULT_MODEL = 'gpt-4o-mini'

      def initialize(config = {})
        super
        @api_key = config[:api_key] || ENV.fetch('OPENAI_API_KEY', nil)
        raise ArgumentError, 'OpenAI API key is required' unless @api_key

        @client = ::OpenAI::Client.new(access_token: @api_key)
        @models_cache = nil
        @models_fetched_at = nil
      end

      def models
        # Cache models for 1 hour
        fetch_models if @models_cache.nil? || @models_fetched_at.nil? || (Time.now - @models_fetched_at) > 3600
        @models_cache
      end

      protected

      def perform_completion(messages, options)
        model = options[:model] || @config[:model] || DEFAULT_MODEL
        temperature = options[:temperature] || @config[:temperature] || 0.7
        max_tokens = options[:max_tokens] || @config[:max_tokens] || 4096

        # Prepare request parameters
        params = {
          model: model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens
        }

        # Add response format if specified
        params[:response_format] = options[:response_format] if options[:response_format]

        # Add tools if provided
        if options[:tools]
          params[:tools] = options[:tools]
          params[:tool_choice] = options[:tool_choice] if options[:tool_choice]
        end

        # Make API call
        response = @client.chat(parameters: params)

        # Format response
        format_response(response, model)
      rescue ::Faraday::Error => e
        handle_api_error(e)
      end

      def stream_complete(prompt, **options, &block)
        messages = prepare_messages(prompt, options[:messages])
        model = options[:model] || @config[:model] || DEFAULT_MODEL
        temperature = options[:temperature] || @config[:temperature] || 0.7
        max_tokens = options[:max_tokens] || @config[:max_tokens] || 4096

        # Prepare streaming request
        params = {
          model: model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens,
          stream: proc do |chunk, _bytesize|
            # Extract content from chunk
            if chunk.dig('choices', 0, 'delta', 'content')
              content = chunk.dig('choices', 0, 'delta', 'content')
              block.call(content) if block_given?
            end
          end
        }

        # Make streaming API call
        @client.chat(parameters: params)
      rescue ::Faraday::Error => e
        handle_api_error(e)
      end

      private

      def fetch_models
        response = @client.models.list

        @models_cache = {}
        response['data'].each do |model|
          # Filter for chat models only
          next unless model['id'].include?('gpt') || model['id'].include?('o1')

          @models_cache[model['id']] = {
            name: model['id'],
            created: model['created'],
            owned_by: model['owned_by']
          }
        end

        @models_fetched_at = Time.now
        @models_cache
      rescue StandardError => e
        Desiru.logger.warn("Failed to fetch OpenAI models: #{e.message}")
        # Fallback to commonly used models
        @models_cache = {
          'gpt-4o-mini' => { name: 'GPT-4o Mini' },
          'gpt-4o' => { name: 'GPT-4o' },
          'gpt-4-turbo' => { name: 'GPT-4 Turbo' },
          'gpt-4' => { name: 'GPT-4' },
          'gpt-3.5-turbo' => { name: 'GPT-3.5 Turbo' }
        }
        @models_fetched_at = Time.now
        @models_cache
      end

      def format_response(response, model)
        # Extract content and usage regardless of response structure
        content = response.dig('choices', 0, 'message', 'content') || ''
        usage = response['usage'] || {}

        {
          content: content,
          raw: response,
          model: model,
          usage: {
            prompt_tokens: usage['prompt_tokens'] || 0,
            completion_tokens: usage['completion_tokens'] || 0,
            total_tokens: usage['total_tokens'] || 0
          }
        }
      end

      def handle_api_error(error)
        case error
        when ::Faraday::UnauthorizedError
          raise AuthenticationError, 'Invalid OpenAI API key'
        when ::Faraday::BadRequestError
          raise InvalidRequestError, "Invalid request: #{error.message}"
        when ::Faraday::TooManyRequestsError
          raise RateLimitError, 'OpenAI API rate limit exceeded'
        else
          raise APIError, "OpenAI API error: #{error.message}"
        end
      end
    end
  end
end
