#!/usr/bin/env ruby
# frozen_string_literal: true

require 'bundler/setup'
require 'desiru'
require 'rack'
require 'rack/handler/webrick'

# This example demonstrates how to create a REST API using Desiru's Grape integration

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY'] || 'your-api-key',
    model: 'gpt-3.5-turbo'
  )
end

# Create some Desiru modules

# Simple Q&A module
qa_module = Desiru::Modules::Predict.new(
  Desiru::Signature.new(
    'question: string -> answer: string',
    descriptions: {
      question: 'The question to answer',
      answer: 'The generated answer'
    }
  )
)

# Summarization module
summarizer = Desiru::Modules::ChainOfThought.new(
  Desiru::Signature.new(
    'text: string, max_words: int -> summary: string, key_points: list[str]',
    descriptions: {
      text: 'The text to summarize',
      max_words: 'Maximum words in the summary',
      summary: 'A concise summary',
      key_points: 'Key points from the text'
    }
  )
)

# Classification module
classifier = Desiru::Modules::Predict.new(
  Desiru::Signature.new(
    "text: string -> category: Literal['technical', 'business', 'general'], confidence: float",
    descriptions: {
      text: 'Text to classify',
      category: 'The category of the text',
      confidence: 'Confidence score (0-1)'
    }
  )
)

# Create the API
api = Desiru::API.create(async_enabled: true, stream_enabled: true) do
  # Register modules with their endpoints
  register_module '/qa', qa_module,
                  description: 'Answer questions using AI'

  register_module '/summarize', summarizer,
                  description: 'Summarize text with key points extraction'

  register_module '/classify', classifier,
                  description: 'Classify text into categories'
end

# Create a Rack app
app = api.to_rack_app

# Add some middleware for logging
logged_app = Rack::Builder.new do
  use Rack::Logger
  use Rack::CommonLogger

  map '/' do
    run proc { |env|
      if env['PATH_INFO'] == '/'
        [200, { 'Content-Type' => 'text/html' }, [<<~HTML]]
                    <!DOCTYPE html>
                    <html>
                    <head>
                      <title>Desiru REST API</title>
                      <style>
                        body { font-family: Arial, sans-serif; margin: 40px; }
                        h1 { color: #333; }
                        .endpoint { background: #f4f4f4; padding: 10px; margin: 10px 0; border-radius: 5px; }
                        code { background: #e0e0e0; padding: 2px 5px; border-radius: 3px; }
                      </style>
                    </head>
                    <body>
                      <h1>Desiru REST API</h1>
                      <p>Welcome to the Desiru REST API powered by Grape!</p>
          #{'            '}
                      <h2>Available Endpoints:</h2>
          #{'            '}
                      <div class="endpoint">
                        <h3>POST /api/v1/qa</h3>
                        <p>Answer questions using AI</p>
                        <p>Parameters: <code>question</code> (string), <code>async</code> (boolean, optional)</p>
                      </div>
          #{'            '}
                      <div class="endpoint">
                        <h3>POST /api/v1/summarize</h3>
                        <p>Summarize text with key points extraction</p>
                        <p>Parameters: <code>text</code> (string), <code>max_words</code> (integer), <code>async</code> (boolean, optional)</p>
                      </div>
          #{'            '}
                      <div class="endpoint">
                        <h3>POST /api/v1/classify</h3>
                        <p>Classify text into categories</p>
                        <p>Parameters: <code>text</code> (string), <code>async</code> (boolean, optional)</p>
                      </div>
          #{'            '}
                      <div class="endpoint">
                        <h3>GET /api/v1/jobs/:id</h3>
                        <p>Check status of async jobs</p>
                      </div>
          #{'            '}
                      <div class="endpoint">
                        <h3>POST /api/v1/stream/*</h3>
                        <p>Streaming versions of all endpoints (Server-Sent Events)</p>
                      </div>
          #{'            '}
                      <h2>Example Usage:</h2>
                      <pre>
          # Synchronous request
          curl -X POST http://localhost:9292/api/v1/qa \\
            -H "Content-Type: application/json" \\
            -d '{"question": "What is Ruby?"}'

          # Async request
          curl -X POST http://localhost:9292/api/v1/summarize \\
            -H "Content-Type: application/json" \\
            -d '{"text": "Long text here...", "max_words": 100, "async": true}'

          # Check job status
          curl http://localhost:9292/api/v1/jobs/JOB_ID

          # Streaming request
          curl -X POST http://localhost:9292/api/v1/stream/qa \\
            -H "Content-Type: application/json" \\
            -H "Accept: text/event-stream" \\
            -d '{"question": "What is Ruby?"}'
                      </pre>
                    </body>
                    </html>
        HTML
      else
        [404, { 'Content-Type' => 'text/plain' }, ['Not Found']]
      end
    }
  end

  run app
end

# Start the server
if __FILE__ == $0
  puts "Starting Desiru REST API server..."
  puts "Visit http://localhost:9292 for documentation"
  puts "API endpoints available at http://localhost:9292/api/v1/*"
  puts "Press Ctrl+C to stop"

  # Run the server
  Rack::Server.start(
    app: logged_app,
    Port: ENV['PORT'] || 9292,
    Host: '0.0.0.0'
  )
end
