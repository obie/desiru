#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'rack'
require 'rack/handler/webrick'
require 'rack/throttle'
require 'jwt'

# Advanced REST API example with authentication, rate limiting, and custom middleware

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY'] || 'your-api-key',
    model: 'gpt-3.5-turbo'
  )
  config.redis_url = ENV['REDIS_URL'] || 'redis://localhost:6379'
end

# Custom authentication middleware
class AuthMiddleware
  def initialize(app)
    @app = app
    @secret = ENV['JWT_SECRET'] || 'your-secret-key'
  end

  def call(env)
    # Skip auth for health check and root
    return @app.call(env) if env['PATH_INFO'] =~ %r{^(/|/api/v1/health)$}

    auth_header = env['HTTP_AUTHORIZATION']

    if auth_header&.start_with?('Bearer ')
      token = auth_header.split[1]

      begin
        payload = JWT.decode(token, @secret, true, algorithm: 'HS256')[0]
        env['current_user'] = payload['user_id']
        env['user_tier'] = payload['tier'] || 'free'
        @app.call(env)
      rescue JWT::DecodeError
        [401, { 'Content-Type' => 'application/json' }, [{ error: 'Invalid token' }.to_json]]
      end
    else
      [401, { 'Content-Type' => 'application/json' }, [{ error: 'Authentication required' }.to_json]]
    end
  end
end

# Custom rate limiter based on user tier
class TieredRateLimiter < Rack::Throttle::Hourly
  def initialize(app, options = {})
    super
  end

  def max_per_window(request)
    case request.env['user_tier']
    when 'premium'
      1000
    when 'standard'
      100
    else
      10 # free tier
    end
  end

  def client_identifier(request)
    request.env['current_user'] || 'anonymous'
  end
end

# Create advanced Desiru modules with validation

# Enhanced Q&A module with context
Desiru::Modules::ChainOfThought.new(
  Desiru::Signature.new(
    'question: string, context: list[str] -> answer: string, sources: list[int], confidence: float',
    descriptions: {
      question: 'The question to answer',
      context: 'Optional context documents',
      answer: 'The generated answer',
      sources: 'Indices of context documents used',
      confidence: 'Answer confidence (0-1)'
    }
  )
)

# Multi-language translation
Desiru::Modules::Predict.new(
  Desiru::Signature.new(
    "text: string, target_language: Literal['es', 'fr', 'de', 'ja', 'zh'] -> translation: string, detected_language: string",
    descriptions: {
      text: 'Text to translate',
      target_language: 'Target language code',
      translation: 'Translated text',
      detected_language: 'Detected source language'
    }
  )
)

# Code analysis module
Desiru::Modules::ChainOfThought.new(
  Desiru::Signature.new(
    'code: string, language: string -> issues: list[str], suggestions: list[str], complexity: int',
    descriptions: {
      code: 'Source code to analyze',
      language: 'Programming language',
      issues: 'Potential issues found',
      suggestions: 'Improvement suggestions',
      complexity: 'Cyclomatic complexity estimate'
    }
  )
)

# Custom Grape API with enhanced features
class AdvancedAPI < Grape::API
  format :json
  prefix :api
  version 'v1', using: :path

  # Global exception handling
  rescue_from :all do |e|
    error!({ error: 'Internal server error', message: e.message }, 500)
  end

  rescue_from Grape::Exceptions::ValidationErrors do |e|
    error!({ error: 'Validation failed', details: e.full_messages }, 422)
  end

  helpers do
    def current_user
      env['current_user']
    end

    def user_tier
      env['user_tier'] || 'free'
    end

    def check_tier_access(required_tier)
      tier_levels = { 'free' => 0, 'standard' => 1, 'premium' => 2 }

      return unless tier_levels[user_tier] < tier_levels[required_tier]

      error!({ error: "This endpoint requires #{required_tier} tier or higher" }, 403)
    end

    def log_usage(endpoint, _params)
      # Log API usage for analytics
      puts "[API Usage] User: #{current_user}, Endpoint: #{endpoint}, Tier: #{user_tier}"
    end
  end

  before do
    # Log all requests
    log_usage(request.path, params)
  end

  # Health check with system info
  desc 'Health check with system information'
  get '/health' do
    {
      status: 'ok',
      timestamp: Time.now.iso8601,
      version: Desiru::VERSION,
      redis_connected: Desiru.redis_connected?,
      user_tier: user_tier
    }
  end

  # Q&A endpoint with context support
  desc 'Answer questions with optional context'
  params do
    requires :question, type: String, desc: 'Question to answer'
    optional :context, type: [String], desc: 'Context documents'
    optional :async, type: Boolean, desc: 'Process asynchronously'
  end
  post '/qa' do
    inputs = {
      question: params[:question],
      context: params[:context] || []
    }

    if params[:async]
      result = qa_with_context.call_async(inputs)
      {
        job_id: result.job_id,
        status_url: "/api/v1/jobs/#{result.job_id}"
      }
    else
      result = qa_with_context.call(inputs)
      result.merge(user_tier: user_tier)
    end
  end

  # Translation endpoint (premium feature)
  desc 'Translate text (Premium tier required)'
  params do
    requires :text, type: String, desc: 'Text to translate'
    requires :target_language, type: String, values: %w[es fr de ja zh]
  end
  post '/translate' do
    check_tier_access('premium')

    result = translator.call(
      text: params[:text],
      target_language: params[:target_language]
    )

    result
  end

  # Code analysis endpoint
  desc 'Analyze code for issues and improvements'
  params do
    requires :code, type: String, desc: 'Source code'
    requires :language, type: String, desc: 'Programming language'
  end
  post '/analyze-code' do
    check_tier_access('standard')

    result = code_analyzer.call(
      code: params[:code],
      language: params[:language]
    )

    result
  end

  # Batch processing endpoint
  desc 'Process multiple requests in batch'
  params do
    requires :requests, type: Array do
      requires :endpoint, type: String, values: ['/qa', '/translate', '/analyze-code']
      requires :params, type: Hash
    end
  end
  post '/batch' do
    check_tier_access('premium')

    max_batch_size = 10
    error!({ error: "Batch size exceeds maximum of #{max_batch_size}" }, 422) if params[:requests].size > max_batch_size

    # Process batch asynchronously
    batch_job_id = SecureRandom.uuid

    # In a real implementation, this would queue a background job
    {
      batch_id: batch_job_id,
      request_count: params[:requests].size,
      status_url: "/api/v1/batches/#{batch_job_id}"
    }
  end

  # Admin endpoints
  namespace :admin do
    before do
      # Extra admin check
      error!({ error: 'Admin access required' }, 403) unless current_user&.start_with?('admin_')
    end

    desc 'Get usage statistics'
    get '/stats' do
      {
        total_requests: 12_345,
        requests_today: 543,
        active_users: 89,
        avg_response_time: 1.23
      }
    end
  end
end

# Create the application
app = Rack::Builder.new do
  # Logging
  use Rack::Logger
  use Rack::CommonLogger

  # CORS support
  use Rack::Cors do
    allow do
      origins '*'
      resource '*',
               headers: :any,
               methods: %i[get post put delete options],
               expose: %w[X-Rate-Limit-Remaining X-Rate-Limit-Reset]
    end
  end

  # Authentication
  use AuthMiddleware

  # Rate limiting
  use TieredRateLimiter,
      cache: Desiru.redis,
      key_prefix: :throttle

  # Mount the API
  run AdvancedAPI
end

# Utility to generate JWT tokens for testing
def generate_token(user_id, tier = 'free')
  secret = ENV['JWT_SECRET'] || 'your-secret-key'
  payload = {
    user_id: user_id,
    tier: tier,
    iat: Time.now.to_i,
    exp: Time.now.to_i + 3600 # 1 hour expiration
  }
  JWT.encode(payload, secret, 'HS256')
end

if __FILE__ == $PROGRAM_NAME
  puts "Starting Advanced Desiru REST API server..."
  puts "\nExample tokens for testing:"
  puts "Free tier:    Bearer #{generate_token('user123', 'free')}"
  puts "Standard tier: Bearer #{generate_token('user456', 'standard')}"
  puts "Premium tier:  Bearer #{generate_token('user789', 'premium')}"
  puts "Admin:         Bearer #{generate_token('admin_001', 'premium')}"
  puts "\nExample requests:"
  puts "curl -H 'Authorization: Bearer TOKEN' http://localhost:9292/api/v1/health"
  puts "\nPress Ctrl+C to stop"

  Rack::Server.start(
    app: app,
    Port: ENV['PORT'] || 9292,
    Host: '0.0.0.0'
  )
end
