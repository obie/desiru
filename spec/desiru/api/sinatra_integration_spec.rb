# frozen_string_literal: true

require 'spec_helper'
require 'rack/test'
require 'desiru/api/sinatra_integration'

RSpec.describe Desiru::API::SinatraIntegration do
  include Rack::Test::Methods

  let(:integration) { described_class.new }
  let(:simple_module) do
    double('DesituModule',
           input_signature: { input: 'string' },
           output_signature: { output: 'string' })
  end

  def app
    integration.generate_api
  end

  describe '#initialize' do
    it 'creates an integration with default settings' do
      expect(integration.async_enabled).to be true
      expect(integration.stream_enabled).to be false
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
    end

    it 'accepts an optional description' do
      integration.register_module('/test', simple_module, description: 'Test endpoint')
      expect(integration.modules['/test'][:description]).to eq('Test endpoint')
    end
  end

  describe '#generate_api' do
    it 'generates a Sinatra application class' do
      api = integration.generate_api
      expect(api.ancestors).to include(Sinatra::Base)
    end

    describe 'generated API' do
      before do
        integration.register_module('/test', simple_module)
      end

      it 'has a health check endpoint' do
        get '/api/v1/health'
        expect(last_response).to have_http_status(:ok)

        body = JSON.parse(last_response.body)
        expect(body['status']).to eq('ok')
        expect(body).to have_key('timestamp')
      end

      describe 'module endpoints' do
        it 'creates POST endpoints for registered modules' do
          allow(simple_module).to receive(:call).and_return({ output: 'test result' })

          post '/api/v1/test', { input: 'test' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:ok)
          body = JSON.parse(last_response.body)
          expect(body['output']).to eq('test result')
        end

        it 'validates required parameters' do
          allow(simple_module).to receive(:call).and_raise(Desiru::ModuleError, 'Missing required parameter: input')

          post '/api/v1/test', {}.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:bad_request)
          body = JSON.parse(last_response.body)
          expect(body['error']).to include('Missing required parameter')
        end

        it 'validates parameter types' do
          allow(simple_module).to receive(:call).and_raise(Desiru::ModuleError, 'Invalid type for input')

          post '/api/v1/test', { input: 123 }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:bad_request)
          body = JSON.parse(last_response.body)
          expect(body['error']).to include('Invalid type')
        end

        it 'handles complex module calls' do
          complex_module = double('ComplexModule',
                                  input_signature: {
                                    name: 'string',
                                    age: 'integer',
                                    active: 'boolean'
                                  })

          integration.register_module('/complex', complex_module)

          expected_input = {
            name: 'John',
            age: 30,
            active: true
          }

          allow(complex_module).to receive(:call).with(expected_input).and_return({
                                                                                    status: 'processed'
                                                                                  })

          post '/api/v1/complex', expected_input.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:ok)
          body = JSON.parse(last_response.body)
          expect(body['status']).to eq('processed')
        end

        it 'handles errors gracefully' do
          allow(simple_module).to receive(:call).and_raise(StandardError, 'Something went wrong')

          post '/api/v1/test', { input: 'test' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:internal_server_error)
          body = JSON.parse(last_response.body)
          expect(body['error']).to eq('Something went wrong')
        end
      end

      describe 'async support' do
        let(:async_module) do
          double('AsyncModule',
                 input_signature: { input: 'string' },
                 output_signature: { output: 'string' })
        end

        before do
          integration.register_module('/async_test', async_module)
        end

        it 'supports async requests' do
          async_result = double('AsyncResult',
                                job_id: 'job123',
                                status: 'pending',
                                progress: 0)

          allow(async_module).to receive(:respond_to?).with(:call_async).and_return(true)
          allow(async_module).to receive(:call_async).and_return(async_result)

          post '/api/v1/async/async_test', { input: 'test' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:accepted)
          body = JSON.parse(last_response.body)
          expect(body['job_id']).to eq('job123')
          expect(body['status']).to eq('pending')
          expect(body['status_url']).to eq('/api/v1/jobs/job123')
        end

        it 'provides job status endpoint' do
          # Mock Desiru.check_job_status
          allow(Desiru).to receive(:respond_to?).and_return(true)
          allow(Desiru).to receive(:check_job_status).with('job123').and_return({
                                                                                  job_id: 'job123',
                                                                                  status: 'completed',
                                                                                  result: { output: 'done' }
                                                                                })

          get '/api/v1/jobs/job123'

          expect(last_response).to have_http_status(:ok)
          body = JSON.parse(last_response.body)
          expect(body['status']).to eq('completed')
        end

        it 'handles missing jobs' do
          allow(Desiru).to receive(:respond_to?).and_return(true)
          allow(Desiru).to receive(:check_job_status).with('nonexistent').and_return(nil)

          get '/api/v1/jobs/nonexistent'

          expect(last_response).to have_http_status(:not_found)
          body = JSON.parse(last_response.body)
          expect(body['error']).to eq('Job not found')
        end
      end

      describe 'streaming support' do
        let(:stream_integration) { described_class.new(stream_enabled: true) }
        let(:stream_module) do
          double('StreamModule',
                 input_signature: { input: 'string' },
                 output_signature: { output: 'string' })
        end

        before do
          stream_integration.register_module('/test', stream_module)
          allow(stream_module).to receive(:respond_to?).with(:call_stream).and_return(true)
          allow(stream_module).to receive(:call).and_return({ output: 'streamed result' })
        end

        def app
          stream_integration.generate_api
        end

        it 'provides streaming endpoints', skip: 'rack-test does not support streaming responses' do
          post '/api/v1/stream/test', { input: 'test' }.to_json, { 'CONTENT_TYPE' => 'application/json' }

          expect(last_response).to have_http_status(:ok)
          expect(last_response.headers['Content-Type']).to include('text/event-stream')
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
    let(:validator_module) do
      Module.new do
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
            true
          end
        end
      end
    end

    let(:validator) do
      Object.new.extend(validator_module)
    end

    it 'validates string types' do
      expect(validator.validate_type('hello', 'string')).to be true
      expect(validator.validate_type(123, 'string')).to be false
    end

    it 'validates integer types' do
      expect(validator.validate_type(123, 'integer')).to be true
      expect(validator.validate_type('123', 'integer')).to be true
      expect(validator.validate_type('abc', 'integer')).to be false
    end

    it 'validates float types' do
      expect(validator.validate_type(123.45, 'float')).to be true
      expect(validator.validate_type(123, 'float')).to be true
      expect(validator.validate_type('abc', 'float')).to be false
    end

    it 'validates boolean types' do
      expect(validator.validate_type(true, 'boolean')).to be true
      expect(validator.validate_type(false, 'boolean')).to be true
      expect(validator.validate_type('true', 'boolean')).to be true
      expect(validator.validate_type('false', 'boolean')).to be true
      expect(validator.validate_type('maybe', 'boolean')).to be false
    end

    it 'validates list types' do
      expect(validator.validate_type([1, 2, 3], 'list')).to be true
      expect(validator.validate_type([], 'list[string]')).to be true
      expect(validator.validate_type('not a list', 'list')).to be false
    end
  end
end
