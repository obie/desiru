# frozen_string_literal: true

require 'anthropic'

module Desiru
  module Models
    # Anthropic Claude model adapter
    class Anthropic < Base
      DEFAULT_MODEL = 'claude-3-5-haiku-latest'

      def initialize(config = {})
        super
        @api_key = config[:api_key] || ENV.fetch('ANTHROPIC_API_KEY', nil)
        raise ArgumentError, 'Anthropic API key is required' unless @api_key

        @client = ::Anthropic::Client.new(api_key: @api_key)
      end

      def models
        # Anthropic doesn't provide a models endpoint, so we maintain a list
        # This list should be updated periodically as new models are released
        @models ||= {
          # Claude 4 models
          'claude-opus-4-20250514' => {
            name: 'Claude Opus 4',
            max_tokens: 200_000,
            description: 'Most advanced Claude model for complex reasoning'
          },
          'claude-sonnet-4-20250514' => {
            name: 'Claude Sonnet 4',
            max_tokens: 200_000,
            description: 'Latest Sonnet with enhanced capabilities'
          },
          # Claude 3.7 models
          'claude-3-7-sonnet-20250219' => {
            name: 'Claude Sonnet 3.7',
            max_tokens: 200_000,
            description: 'Advanced Sonnet with improved performance'
          },
          'claude-3-7-sonnet-latest' => {
            name: 'Claude Sonnet 3.7 (Latest)',
            max_tokens: 200_000,
            description: 'Latest Claude Sonnet 3.7 model'
          },
          # Claude 3.5 models
          'claude-3-5-haiku-20241022' => {
            name: 'Claude 3.5 Haiku',
            max_tokens: 200_000,
            description: 'Latest Haiku with enhanced speed'
          },
          'claude-3-5-haiku-latest' => {
            name: 'Claude 3.5 Haiku (Latest)',
            max_tokens: 200_000,
            description: 'Latest Claude 3.5 Haiku model'
          },
          'claude-3-5-sonnet-20241022' => {
            name: 'Claude 3.5 Sonnet',
            max_tokens: 200_000,
            description: 'Sonnet with improved capabilities'
          },
          # Legacy Claude 3 models
          'claude-3-haiku-20240307' => {
            name: 'Claude 3 Haiku',
            max_tokens: 200_000,
            description: 'Fast and efficient for simple tasks'
          },
          'claude-3-sonnet-20240229' => {
            name: 'Claude 3 Sonnet',
            max_tokens: 200_000,
            description: 'Balanced performance and capability'
          },
          'claude-3-opus-20240229' => {
            name: 'Claude 3 Opus',
            max_tokens: 200_000,
            description: 'Most capable Claude 3 model for complex tasks'
          }
        }
      end

      protected

      def perform_completion(messages, options)
        model = options[:model] || @config[:model] || DEFAULT_MODEL
        temperature = options[:temperature] || @config[:temperature] || 0.7
        max_tokens = options[:max_tokens] || @config[:max_tokens] || 4096

        # Convert messages to Anthropic format
        system_message, user_messages = format_messages(messages)

        # Prepare request parameters
        params = {
          model: model,
          messages: user_messages,
          max_tokens: max_tokens,
          temperature: temperature
        }

        # Add system message if present
        params[:system] = system_message if system_message

        # Add tools if provided
        if options[:tools]
          params[:tools] = format_tools(options[:tools])
          params[:tool_choice] = options[:tool_choice] if options[:tool_choice]
        end

        # Make API call
        message = @client.messages.create(**params)
        format_response(message, model)
      rescue ::Faraday::Error => e
        handle_api_error(e)
      end

      private

      def format_messages(messages)
        system_message = nil
        user_messages = []

        messages.each do |msg|
          case msg[:role]
          when 'system'
            system_message = msg[:content]
          when 'user'
            user_messages << { role: 'user', content: msg[:content] }
          when 'assistant'
            user_messages << { role: 'assistant', content: msg[:content] }
          end
        end

        [system_message, user_messages]
      end

      def format_tools(tools)
        tools.map do |tool|
          {
            name: tool[:function][:name],
            description: tool[:function][:description],
            input_schema: tool[:function][:parameters]
          }
        end
      end

      def format_response(message, model)
        {
          content: extract_content(message),
          raw: message,
          model: model,
          usage: {
            prompt_tokens: message.usage.input_tokens || 0,
            completion_tokens: message.usage.output_tokens || 0,
            total_tokens: (message.usage.input_tokens || 0) + (message.usage.output_tokens || 0)
          }
        }
      end

      def extract_content(response)
        # Handle different response formats
        if response.is_a?(Hash)
          # Direct API response
          if response['content'].is_a?(Array)
            response['content'].map { |c| c['text'] }.join
          else
            response['content'] || response['completion'] || ''
          end
        else
          # Client wrapper response
          response.content.first.text
        end
      rescue StandardError => e
        Desiru.logger.error("Failed to extract content from Anthropic response: #{e.message}")
        ''
      end

      def handle_api_error(error)
        case error
        when ::Faraday::UnauthorizedError
          raise AuthenticationError, 'Invalid Anthropic API key'
        when ::Faraday::BadRequestError
          raise InvalidRequestError, "Invalid request: #{error.message}"
        when ::Faraday::TooManyRequestsError
          raise RateLimitError, 'Anthropic API rate limit exceeded'
        else
          raise APIError, "Anthropic API error: #{error.message}"
        end
      end
    end
  end
end
