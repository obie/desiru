# frozen_string_literal: true

require 'open_router'

module Desiru
  module Models
    # OpenRouter model adapter - provides access to multiple models through a single API
    class OpenRouter < Base
      DEFAULT_MODEL = 'anthropic/claude-3-haiku'

      def initialize(config = {})
        super
        @api_key = config[:api_key] || ENV.fetch('OPENROUTER_API_KEY', nil)
        raise ArgumentError, 'OpenRouter API key is required' unless @api_key

        # Configure OpenRouter client
        ::OpenRouter.configure do |c|
          c.access_token = @api_key
          c.site_name = config[:site_name] || 'Desiru'
          c.site_url = config[:site_url] || 'https://github.com/obie/desiru'
        end

        @client = ::OpenRouter::Client.new
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

        # Add provider-specific options if needed
        params[:provider] = options[:provider] if options[:provider]

        # Add response format if specified
        params[:response_format] = options[:response_format] if options[:response_format]

        # Add tools if provided (for models that support function calling)
        if options[:tools]
          params[:tools] = options[:tools]
          params[:tool_choice] = options[:tool_choice] if options[:tool_choice]
        end

        # Make API call
        response = @client.complete(params)

        # Format response
        format_response(response, model)
      rescue StandardError => e
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
          stream: true
        }

        # Stream response
        @client.complete(params) do |chunk|
          if chunk.dig('choices', 0, 'delta', 'content')
            content = chunk.dig('choices', 0, 'delta', 'content')
            block.call(content) if block_given?
          end
        end
      rescue StandardError => e
        handle_api_error(e)
      end

      private

      def fetch_models
        # OpenRouter provides models at https://openrouter.ai/api/v1/models
        response = @client.models

        @models_cache = {}
        response['data'].each do |model|
          @models_cache[model['id']] = {
            name: model['name'] || model['id'],
            context_length: model['context_length'],
            pricing: model['pricing'],
            top_provider: model['top_provider']
          }
        end

        @models_fetched_at = Time.now
        @models_cache
      rescue StandardError => e
        Desiru.logger.warn("Failed to fetch OpenRouter models: #{e.message}")
        # Fallback to commonly used models
        @models_cache = {
          'anthropic/claude-3-haiku' => { name: 'Claude 3 Haiku' },
          'anthropic/claude-3-sonnet' => { name: 'Claude 3 Sonnet' },
          'openai/gpt-4o-mini' => { name: 'GPT-4o Mini' },
          'openai/gpt-4o' => { name: 'GPT-4o' },
          'google/gemini-pro' => { name: 'Gemini Pro' }
        }
        @models_fetched_at = Time.now
        @models_cache
      end

      def format_response(response, model)
        # OpenRouter uses OpenAI-compatible response format
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
          raise AuthenticationError, 'Invalid OpenRouter API key'
        when ::Faraday::BadRequestError
          raise InvalidRequestError, "Invalid request: #{error.message}"
        when ::Faraday::TooManyRequestsError
          raise RateLimitError, 'OpenRouter API rate limit exceeded'
        when ::Faraday::PaymentRequiredError
          raise APIError, 'OpenRouter payment required - check your account balance'
        else
          raise APIError, "OpenRouter API error: #{error.message}"
        end
      end
    end
  end
end
