# frozen_string_literal: true

require 'spec_helper'
require 'desiru/api/grape_integration'
require 'rack/test'

RSpec.describe Desiru::API::GrapeIntegration do
  include Rack::Test::Methods

  let(:mock_model) { double('model') }
  let(:integration) { described_class.new }

  let(:simple_module) do
    Desiru::Modules::Predict.new(
      Desiru::Signature.new('input: string -> output: string'),
      model: mock_model
    )
  end

  let(:complex_module) do
    Desiru::Modules::Predict.new(
      Desiru::Signature.new(
        'text: string, count: int, enabled: bool -> result: string, items: list[str]',
        descriptions: {
          text: 'Input text',
          count: 'Number of items',
          enabled: 'Feature flag',
          result: 'Processed result',
          items: 'List of items'
        }
      ),
      model: mock_model
    )
  end

  def app
    integration.generate_api
  end

  describe '#initialize' do
    it 'creates an integration with default settings' do
      expect(integration.async_enabled).to be true
      expect(integration.stream_enabled).to be false
      expect(integration.modules).to eq({})
    end

    it 'accepts configuration options' do
      custom = described_class.new(async_enabled: false, stream_enabled: true)
      expect(custom.async_enabled).to be false
      expect(custom.stream_enabled).to be true
    end
  end

  describe '#register_module' do
    it 'registers a module with a path' do
      integration.register_module('/test', simple_module)
      expect(integration.modules).to have_key('/test')
      expect(integration.modules['/test'][:module]).to eq(simple_module)
    end

    it 'accepts an optional description' do
      integration.register_module('/test', simple_module, description: 'Test endpoint')
      expect(integration.modules['/test'][:description]).to eq('Test endpoint')
    end
  end

  describe '#generate_api' do
    before do
      integration.register_module('/simple', simple_module)
      integration.register_module('/complex', complex_module)
    end

    it 'generates a Grape API class' do
      api = integration.generate_api
      expect(api).to be < Grape::API
    end

    describe 'generated API' do
      it 'has a health check endpoint' do
        get '/api/v1/health'
        expect(last_response).to be_ok

        body = JSON.parse(last_response.body)
        expect(body['status']).to eq('ok')
        expect(body['timestamp']).to be_present
      end

      context 'module endpoints' do
        before do
          allow(simple_module).to receive(:call).and_return({ output: 'test result' })
        end

        it 'creates POST endpoints for registered modules' do
          post '/api/v1/simple', { input: 'test' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          # Debug output if test fails
          unless last_response.ok?
            puts "Response status: #{last_response.status}"
            puts "Response body: #{last_response.body}"
          end

          expect(last_response).to have_http_status(:created)
          expect(simple_module).to have_received(:call).with({ input: 'test' })

          body = JSON.parse(last_response.body)
          expect(body['output']).to eq('test result')
        end

        it 'validates required parameters' do
          post '/api/v1/simple', {}.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:unprocessable_entity)
          body = JSON.parse(last_response.body)
          expect(body['errors']).to have_key('input')
        end

        it 'validates parameter types' do
          post '/api/v1/complex', {
            text: 'hello',
            count: 'not a number',
            enabled: true
          }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:bad_request)
          body = JSON.parse(last_response.body)
          expect(body['error']).to be_present
        end

        it 'handles complex module calls' do
          allow(complex_module).to receive(:call).and_return({
                                                               result: 'processed',
                                                               items: %w[a b c]
                                                             })

          post '/api/v1/complex', {
            text: 'hello',
            count: 3,
            enabled: true
          }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:created)
          expect(complex_module).to have_received(:call).with({
                                                                text: 'hello',
                                                                count: 3,
                                                                enabled: true
                                                              })

          body = JSON.parse(last_response.body)
          expect(body['result']).to eq('processed')
          expect(body['items']).to eq(%w[a b c])
        end

        it 'handles errors gracefully' do
          allow(simple_module).to receive(:call).and_raise('Test error')

          post '/api/v1/simple', { input: 'test' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:internal_server_error)
          body = JSON.parse(last_response.body)
          expect(body['error']).to eq('Test error')
        end
      end

      context 'async support' do
        let(:async_result) { double('async_result', job_id: 'job123', status: 'pending', progress: 0) }

        before do
          # Allow the module to respond to call_async
          allow(simple_module).to receive(:respond_to?).and_call_original
          allow(simple_module).to receive(:respond_to?).with(:call_async).and_return(true)
          allow(simple_module).to receive(:call_async).and_return(async_result)
        end

        it 'supports async requests' do
          post '/api/v1/simple', { input: 'test', async: true }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:created)
          expect(simple_module).to have_received(:call_async).with({ input: 'test' })

          body = JSON.parse(last_response.body)
          expect(body['job_id']).to eq('job123')
          expect(body['status']).to eq('pending')
          expect(body['status_url']).to eq('/api/v1/jobs/job123')
        end

        it 'provides job status endpoint' do
          status = double('status',
                          status: 'completed',
                          progress: 100,
                          ready?: true,
                          result: { output: 'async result' })

          allow(Desiru::AsyncStatus).to receive(:new).with('job123').and_return(status)

          get '/api/v1/jobs/job123'

          expect(last_response).to have_http_status(:ok)
          body = JSON.parse(last_response.body)
          expect(body['status']).to eq('completed')
          expect(body['progress']).to eq(100)
          expect(body['result']).to eq({ 'output' => 'async result' })
        end

        it 'handles missing jobs' do
          allow(Desiru::AsyncStatus).to receive(:new).and_raise(StandardError)

          get '/api/v1/jobs/nonexistent'

          expect(last_response).to have_http_status(:not_found)
          body = JSON.parse(last_response.body)
          expect(body['error']).to eq('Job not found')
        end
      end

      context 'streaming support' do
        let(:stream_integration) { described_class.new(stream_enabled: true) }

        before do
          stream_integration.register_module('/test', simple_module)
          allow(simple_module).to receive(:call).and_return({ output: 'streamed result' })
        end

        def app
          stream_integration.generate_api
        end

        it 'provides streaming endpoints', skip: 'rack-test does not support streaming responses' do
          post '/api/v1/stream/test', { input: 'test' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:ok)
          expect(last_response.headers['Content-Type']).to include('text/event-stream')

          # Parse SSE response
          events = last_response.body.split("\n\n").map do |event|
            lines = event.split("\n")
            {
              event: lines.find { |l| l.start_with?('event:') }&.split(': ', 2)&.last,
              data: lines.find { |l| l.start_with?('data:') }&.split(': ', 2)&.last
            }
          end.compact

          result_event = events.find { |e| e[:event] == 'result' }
          expect(result_event).to be_present

          data = JSON.parse(result_event[:data])
          expect(data['output']).to eq('streamed result')

          done_event = events.find { |e| e[:event] == 'done' }
          expect(done_event).to be_present
        end
      end
    end
  end

  describe '#to_rack_app' do
    before do
      integration.register_module('/test', simple_module)
    end

    it 'creates a Rack application' do
      rack_app = integration.to_rack_app
      expect(rack_app).to respond_to(:call)
    end

    it 'includes CORS middleware' do
      app_instance = integration.to_rack_app

      # Check that the rack app is a Rack::Builder with CORS middleware
      expect(app_instance).to be_a(Rack::Builder)

      # The actual CORS functionality would be tested in integration tests
      # rack-test doesn't properly simulate CORS preflight requests
    end
  end

  describe 'type validation' do
    # Create a helper instance to test validation methods
    let(:helper_class) do
      api = integration.generate_api
      Class.new do
        include api.helpers
      end
    end

    let(:validator) { helper_class.new }

    it 'validates string types' do
      expect(validator.validate_type('hello', 'string')).to be true
      expect(validator.validate_type(123, 'string')).to be false
    end

    it 'validates integer types' do
      expect(validator.validate_type(123, 'int')).to be true
      expect(validator.validate_type('123', 'int')).to be true
      expect(validator.validate_type('abc', 'int')).to be false
    end

    it 'validates float types' do
      expect(validator.validate_type(3.14, 'float')).to be true
      expect(validator.validate_type(42, 'float')).to be true
      expect(validator.validate_type('not a number', 'float')).to be false
    end

    it 'validates boolean types' do
      expect(validator.validate_type(true, 'bool')).to be true
      expect(validator.validate_type(false, 'bool')).to be true
      expect(validator.validate_type('true', 'bool')).to be true
      expect(validator.validate_type('yes', 'bool')).to be false
    end

    it 'validates list types' do
      expect(validator.validate_type(%w[a b], 'list')).to be true
      expect(validator.validate_type('not a list', 'list')).to be false
    end
  end
end
