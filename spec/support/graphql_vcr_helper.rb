# frozen_string_literal: true

require 'vcr'

# VCR helper for GraphQL testing
# Provides utilities for recording and replaying GraphQL interactions
module GraphQLVCRHelper
  # Configure VCR for GraphQL testing
  def self.configure_vcr
    VCR.configure do |config|
      config.cassette_library_dir = 'spec/vcr_cassettes/graphql'
      config.hook_into :webmock
      config.configure_rspec_metadata!

      # Custom matcher for GraphQL requests
      config.register_request_matcher :graphql_operation do |request1, request2|
        extract_operation_name(request1) == extract_operation_name(request2)
      end

      # Filter sensitive data
      config.filter_sensitive_data('<API_KEY>') { ENV.fetch('OPENAI_API_KEY', nil) }
      config.filter_sensitive_data('<API_KEY>') { ENV.fetch('ANTHROPIC_API_KEY', nil) }

      # Default cassette options for GraphQL
      config.default_cassette_options = {
        record: :new_episodes,
        match_requests_on: %i[method uri graphql_operation],
        allow_playback_repeats: true
      }
    end
  end

  # Extract operation name from GraphQL request
  def self.extract_operation_name(request)
    return nil unless request.body

    body = begin
      JSON.parse(request.body)
    rescue StandardError
      nil
    end
    return nil unless body.is_a?(Hash)

    # Try to extract operation name from query
    query = body['query'] || ''
    operation_match = query.match(/(?:query|mutation|subscription)\s+(\w+)/)
    operation_match ? operation_match[1] : 'anonymous'
  end

  # Wrap GraphQL execution with VCR cassette
  def with_graphql_vcr(cassette_name, options = {}, &)
    VCR.use_cassette("graphql/#{cassette_name}", options, &)
  end

  # Helper to record GraphQL batch operations
  def record_graphql_batch(cassette_name, &block)
    with_graphql_vcr(cassette_name, record: :new_episodes) do
      # Ensure DataLoader batching happens within VCR context
      result = nil
      if defined?(Desiru::GraphQL::DataLoader)
        data_loader = Desiru::GraphQL::DataLoader.new
        original_loader = Thread.current[:graphql_data_loader]
        Thread.current[:graphql_data_loader] = data_loader

        begin
          result = block.call(data_loader)
          data_loader.perform_loads
        ensure
          Thread.current[:graphql_data_loader] = original_loader
        end
      else
        result = block.call
      end
      result
    end
  end

  # Helper to assert GraphQL response structure
  def assert_graphql_success(result)
    expect(result).to be_a(Hash)
    expect(result['errors']).to be_nil
    expect(result['data']).not_to be_nil
  end

  # Helper to assert GraphQL errors
  def assert_graphql_errors(result, expected_count = nil)
    expect(result).to be_a(Hash)
    expect(result['errors']).to be_a(Array)
    expect(result['errors']).not_to be_empty

    return unless expected_count

    expect(result['errors'].size).to eq(expected_count)
  end
end

# Include in RSpec if available
if defined?(RSpec)
  RSpec.configure do |config|
    config.include GraphQLVCRHelper

    config.before(:suite) do
      GraphQLVCRHelper.configure_vcr
    end
  end
end
