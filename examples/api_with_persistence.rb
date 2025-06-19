#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'desiru/persistence'
require 'rack'

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY'] || 'your-api-key',
    model: 'gpt-3.5-turbo'
  )
end

# Setup persistence
puts "Setting up database..."
Desiru::Persistence.database_url = 'sqlite://api_tracking.db'
Desiru::Persistence.connect!
Desiru::Persistence.migrate!

# Define a simple module
class TextAnalyzer < Desiru::Module
  signature 'TextAnalyzer', 'Analyze text sentiment and key themes'

  input 'text', type: 'string', desc: 'Text to analyze'

  output 'sentiment', type: 'string', desc: 'Overall sentiment (positive/negative/neutral)'
  output 'themes', type: 'list[string]', desc: 'Key themes identified'
  output 'confidence', type: 'float', desc: 'Confidence score (0-1)'

  def forward(_text:)
    # Simulate analysis
    {
      sentiment: %w[positive negative neutral].sample,
      themes: %w[technology business health education].sample(2),
      confidence: rand(0.7..0.95).round(2)
    }
  end
end

# Create API with persistence tracking
api = Desiru::API.create(framework: :sinatra) do
  register_module '/analyze', TextAnalyzer.new,
                  description: 'Analyze text sentiment and themes'
end

# Add persistence tracking
app = api.with_persistence(enabled: true)

# Add a simple UI endpoint
ui_app = Rack::Builder.new do
  use Desiru::API::PersistenceMiddleware

  map '/' do
    run lambda { |_env|
      html = <<~HTML
              <!DOCTYPE html>
              <html>
              <head>
                <title>Desiru API with Persistence</title>
                <style>
                  body { font-family: Arial, sans-serif; margin: 40px; }
                  .endpoint { background: #f0f0f0; padding: 10px; margin: 10px 0; }
                  .stats { background: #e0f0ff; padding: 15px; margin: 20px 0; }
                  pre { background: #f5f5f5; padding: 10px; overflow-x: auto; }
                </style>
              </head>
              <body>
                <h1>Desiru API with Persistence Tracking</h1>
        #{'        '}
                <div class="endpoint">
                  <h2>Text Analysis Endpoint</h2>
                  <p><strong>POST /api/v1/analyze</strong></p>
                  <p>Analyze text sentiment and extract key themes</p>
                  <pre>curl -X POST http://localhost:9294/api/v1/analyze \\
        -H "Content-Type: application/json" \\
        -d '{"text": "This is an amazing product that exceeds expectations!"}'</pre>
                </div>
        #{'        '}
                <div class="stats">
                  <h2>API Statistics</h2>
                  <ul>
                    <li>Total API Requests: #{Desiru::Persistence[:api_requests].count}</li>
                    <li>Module Executions: #{Desiru::Persistence[:module_executions].count}</li>
                    <li>Success Rate: #{Desiru::Persistence[:module_executions].success_rate}%</li>
                    <li>Average Response Time: #{Desiru::Persistence[:api_requests].average_response_time || 0}s</li>
                  </ul>
                </div>
        #{'        '}
                <div class="endpoint">
                  <h2>Recent Requests</h2>
                  <ul>
                    #{Desiru::Persistence[:api_requests].recent(5).map do |r|
                      "<li>#{r.method} #{r.path} - #{r.status_code} (#{r.response_time ? "#{(r.response_time * 1000).round}ms" : 'N/A'})</li>"
                    end.join("\n              ")}
                  </ul>
                </div>
              </body>
              </html>
      HTML

      [200, { 'Content-Type' => 'text/html' }, [html]]
    }
  end

  map '/api' do
    run app
  end
end

puts "Starting API server with persistence tracking on http://localhost:9294"
puts "\nEndpoints:"
puts "  GET  /                - Web UI with statistics"
puts "  POST /api/v1/analyze  - Text analysis endpoint"
puts "  GET  /api/v1/health   - Health check"
puts "\nAll API requests are automatically tracked in the database!"
puts "Press Ctrl+C to stop the server"

# Start the server
Rack::Handler::WEBrick.run ui_app, Port: 9294
