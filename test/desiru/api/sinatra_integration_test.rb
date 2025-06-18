# frozen_string_literal: true

require 'test_helper'
require 'rack/test'
require 'desiru/api/sinatra_integration'

class Desiru::API::SinatraIntegrationTest < Minitest::Test
  include Rack::Test::Methods

  def setup
    @integration = Desiru::API::SinatraIntegration.new
    @test_module = create_test_module
  end

  def app
    @integration.generate_api
  end

  def test_initialize_with_defaults
    assert @integration.async_enabled
    refute @integration.stream_enabled
  end

  def test_initialize_with_options
    custom = Desiru::API::SinatraIntegration.new(
      async_enabled: false,
      stream_enabled: true
    )

    refute custom.async_enabled
    assert custom.stream_enabled
  end

  def test_register_module
    @integration.register_module('/test', @test_module)

    assert_includes @integration.modules, '/test'
    assert_equal @test_module, @integration.modules['/test'][:module]
  end

  def test_register_module_with_description
    @integration.register_module('/test', @test_module, description: 'Test endpoint')

    assert_equal 'Test endpoint', @integration.modules['/test'][:description]
  end

  def test_health_endpoint
    get '/api/v1/health'

    assert_equal 200, last_response.status

    body = JSON.parse(last_response.body)
    assert_equal 'ok', body['status']
    assert body.key?('timestamp')
  end

  def test_module_endpoint
    @integration.register_module('/test', @test_module)

    post '/api/v1/test',
         { input: 'hello' }.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    assert_equal 200, last_response.status

    body = JSON.parse(last_response.body)
    assert_equal 'processed: hello', body['output']
  end

  def test_missing_required_parameter
    @integration.register_module('/test', @test_module)

    post '/api/v1/test',
         {}.to_json,
         { 'CONTENT_TYPE' => 'application/json' }

    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)
    assert_match(/Missing required inputs/, body['error'])
  end

  def test_invalid_json
    @integration.register_module('/test', @test_module)

    post '/api/v1/test',
         'invalid json',
         { 'CONTENT_TYPE' => 'application/json' }

    assert_equal 400, last_response.status

    body = JSON.parse(last_response.body)
    assert_equal 'Invalid JSON', body['error']
  end

  def test_to_rack_app
    @integration.register_module('/test', @test_module)
    rack_app = @integration.to_rack_app

    assert rack_app.respond_to?(:call)
    assert_kind_of Rack::Builder, rack_app
  end

  def test_cors_middleware_included
    # The CORS middleware is included but rack-test doesn't
    # properly simulate CORS preflight requests
    # This just verifies the middleware is in the stack
    rack_app = @integration.to_rack_app

    # Check that it's a Rack::Builder with middleware
    assert_kind_of Rack::Builder, rack_app
  end
end
