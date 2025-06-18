# frozen_string_literal: true

require 'raix'
require 'faraday'
require 'faraday/retry'
require 'openai'

module Desiru
  module Models
    # Adapter for Raix gem integration
    # Provides unified interface to OpenAI, Anthropic, and OpenRouter via Raix
    # Uses modern Raix patterns with direct OpenAI::Client configuration
    class RaixAdapter < Base
      def initialize(api_key: nil, provider: :openai, uri_base: nil, **config)
        @api_key = api_key || fetch_api_key(provider)
        @provider = provider
        @uri_base = uri_base || fetch_uri_base(provider)

        super(config)
        configure_raix!
      end

      def complete(prompt, **options)
        opts = build_completion_options(prompt, options)

        response = with_retry do
          client.completions.create(**opts)
        end

        process_response(response)
      end

      def stream_complete(prompt, **options)
        opts = build_completion_options(prompt, options).merge(stream: true)

        with_retry do
          client.completions.create(**opts) do |chunk|
            yield process_stream_chunk(chunk)
          end
        end
      end

      def models
        case provider
        when :openai
          %w[gpt-4-turbo gpt-4 gpt-3.5-turbo gpt-4o gpt-4o-mini]
        when :anthropic
          %w[claude-3-opus-20240229 claude-3-sonnet-20240229 claude-3-haiku-20240307]
        when :openrouter
          # OpenRouter supports many models with provider prefixes
          %w[anthropic/claude-3-opus openai/gpt-4-turbo google/gemini-pro meta-llama/llama-3-70b]
        else
          []
        end
      end

      protected

      def default_config
        super.merge(
          model: 'gpt-4-turbo-preview',
          response_format: nil,
          tools: nil,
          tool_choice: nil
        )
      end

      def build_client
        # Modern Raix uses direct configuration, not separate client instances
        # The client is accessed through Raix after configuration
        ::Raix
      end

      def configure_raix!
        ::Raix.configure do |raix_config|
          raix_config.openai_client = build_openai_client
        end
      end

      def build_openai_client
        ::OpenAI::Client.new(
          access_token: @api_key,
          uri_base: @uri_base
        ) do |f|
          # Add retry middleware
          f.request(:retry, {
                      max: config[:max_retries] || 3,
                      interval: 0.05,
                      interval_randomness: 0.5,
                      backoff_factor: 2
                    })

          # Add logging in debug mode
          if ENV['DEBUG'] || config[:debug]
            f.response(:logger, config[:logger] || Logger.new($stdout), {
                         headers: false,
                         bodies: true,
                         errors: true
                       }) do |logger|
              logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
            end
          end
        end
      end

      def fetch_api_key(provider)
        case provider
        when :openai
          ENV.fetch('OPENAI_API_KEY', nil)
        when :anthropic
          ENV.fetch('ANTHROPIC_API_KEY', nil)
        when :openrouter
          ENV.fetch('OPENROUTER_API_KEY', nil)
        else
          ENV.fetch("#{provider.to_s.upcase}_API_KEY", nil)
        end
      end

      def fetch_uri_base(provider)
        case provider
        when :openai
          ENV['OPENAI_API_BASE'] || 'https://api.openai.com/v1'
        when :anthropic
          ENV['ANTHROPIC_API_BASE'] || 'https://api.anthropic.com/v1'
        when :openrouter
          ENV['OPENROUTER_API_BASE'] || 'https://openrouter.ai/api/v1'
        else
          ENV.fetch("#{provider.to_s.upcase}_API_BASE", nil)
        end
      end

      def validate_config!
        raise ConfigurationError, 'API key is required' if @api_key.nil? || @api_key.empty?
        raise ConfigurationError, 'Model must be specified' if config[:model].nil?
      end

      private

      attr_reader :provider

      def build_completion_options(prompt, options)
        messages = build_messages(prompt, options[:demos] || [])

        {
          model: options[:model] || config[:model],
          messages: messages,
          temperature: options[:temperature] || config[:temperature],
          max_tokens: options[:max_tokens] || config[:max_tokens],
          response_format: options[:response_format] || config[:response_format],
          tools: options[:tools] || config[:tools],
          tool_choice: options[:tool_choice] || config[:tool_choice]
        }.compact
      end

      def build_messages(prompt, demos)
        messages = []

        # Add system message if provided
        messages << { role: 'system', content: prompt[:system] } if prompt[:system]

        # Add demonstrations
        demos.each do |demo|
          messages << { role: 'user', content: demo[:input] }
          messages << { role: 'assistant', content: demo[:output] }
        end

        # Add current prompt
        messages << { role: 'user', content: prompt[:user] || prompt[:content] || prompt }

        messages
      end

      def process_response(response)
        content = response.dig('choices', 0, 'message', 'content')
        usage = response['usage']

        increment_stats(usage['total_tokens']) if usage

        {
          content: content,
          raw: response,
          model: response['model'],
          usage: usage
        }
      end

      def process_stream_chunk(chunk)
        content = chunk.dig('choices', 0, 'delta', 'content')

        {
          content: content,
          finished: chunk.dig('choices', 0, 'finish_reason').present?
        }
      end
    end

    # Convenience classes for specific providers
    class OpenAI < RaixAdapter
      def initialize(api_key: nil, **config)
        super(api_key: api_key, provider: :openai, **config)
      end
    end

    class OpenRouter < RaixAdapter
      def initialize(api_key: nil, **config)
        super(api_key: api_key, provider: :openrouter, **config)
      end
    end
  end
end
