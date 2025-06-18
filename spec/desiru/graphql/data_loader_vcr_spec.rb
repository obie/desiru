# frozen_string_literal: true

require 'spec_helper'
require 'desiru/graphql/data_loader'
require 'desiru/graphql/schema_generator'
require 'desiru/graphql/executor'
require_relative '../../support/graphql_vcr_helper'

RSpec.describe 'GraphQL DataLoader with VCR', :vcr do
  # Mock module that simulates API calls
  let(:api_module) do
    Class.new do
      attr_reader :signature

      def initialize(signature)
        @signature = signature
      end

      def call(inputs)
        # Simulate an external API call that would be recorded by VCR
        {
          result: "API response for: #{inputs[:query]}",
          cached: false,
          timestamp: Time.now.to_f
        }
      end

      def batch_forward(inputs_array)
        # Simulate batch API call
        inputs_array.map do |inputs|
          {
            result: "Batch API response for: #{inputs[:query]}",
            cached: false,
            timestamp: Time.now.to_f
          }
        end
      end

      def self.name
        'APIModule'
      end
    end
  end
  let(:schema) { schema_generator.generate_schema }
  let(:executor) { Desiru::GraphQL::Executor.new(schema, data_loader: data_loader) }

  let(:schema_generator) { Desiru::GraphQL::SchemaGenerator.new }
  let(:data_loader) { Desiru::GraphQL::DataLoader.new }
  let(:signature) { Desiru::Signature.new('query: string -> result: string, cached: bool, timestamp: float') }
  let(:module_instance) { api_module.new(signature) }

  before do
    schema_generator.register_signature('fetchData', signature)
    schema_generator.register_module('fetchData', module_instance)
  end

  describe 'VCR recording and playback' do
    it 'records API calls on first run and replays on subsequent runs' do
      query = <<~GRAPHQL
        {
          data1: fetchData(query: "test1") { result cached timestamp }
          data2: fetchData(query: "test2") { result cached timestamp }
          data3: fetchData(query: "test1") { result cached timestamp }
        }
      GRAPHQL

      # First execution - records to VCR cassette
      result1 = nil
      timestamp1 = nil

      with_graphql_vcr('data_loader_api_calls') do
        result1 = executor.execute(query)
        assert_graphql_success(result1)
        timestamp1 = result1['data']['data1']['timestamp']
      end

      # Second execution - plays back from VCR cassette
      result2 = nil
      timestamp2 = nil

      with_graphql_vcr('data_loader_api_calls') do
        result2 = executor.execute(query)
        assert_graphql_success(result2)
        timestamp2 = result2['data']['data1']['timestamp']
      end

      # Results should be identical (including timestamps) due to VCR playback
      expect(result2).to eq(result1)
      expect(timestamp2).to eq(timestamp1)

      # Verify deduplication still works with VCR
      expect(result1['data']['data1']['result']).to eq(result1['data']['data3']['result'])
    end

    it 'handles batch operations with VCR' do
      query = <<~GRAPHQL
        {
          item1: fetchData(query: "batch1") { result }
          item2: fetchData(query: "batch2") { result }
          item3: fetchData(query: "batch3") { result }
          item4: fetchData(query: "batch1") { result }
        }
      GRAPHQL

      result = record_graphql_batch('batch_operations') do |_loader|
        executor.execute(query)
      end

      assert_graphql_success(result)

      # Verify batch results
      expect(result['data']['item1']['result']).to include('Batch API response')
      expect(result['data']['item1']['result']).to eq(result['data']['item4']['result'])
    end

    it 'segregates different operations into different cassettes' do
      query1 = <<~GRAPHQL
        query UserData {
          user: fetchData(query: "user123") { result }
        }
      GRAPHQL

      query2 = <<~GRAPHQL
        query PostData {
          post: fetchData(query: "post456") { result }
        }
      GRAPHQL

      # Record different operations in different cassettes
      user_result = with_graphql_vcr('user_operations') do
        executor.execute(query1)
      end

      post_result = with_graphql_vcr('post_operations') do
        executor.execute(query2)
      end

      assert_graphql_success(user_result)
      assert_graphql_success(post_result)

      # Results should be different
      expect(user_result['data']['user']['result']).not_to eq(post_result['data']['post']['result'])
    end
  end

  describe 'VCR with error handling' do
    let(:error_module) do
      Class.new(api_module) do
        def call(inputs)
          raise "API Error: Invalid query" if inputs[:query] == 'error'

          super
        end
      end
    end

    let(:error_module_instance) { error_module.new(signature) }

    before do
      schema_generator.register_module('fetchData', error_module_instance)
    end

    it 'records and replays errors' do
      query = <<~GRAPHQL
        {
          data: fetchData(query: "error") { result }
        }
      GRAPHQL

      # First run - record the error
      result1 = with_graphql_vcr('error_handling') do
        executor.execute(query)
      end

      # Second run - replay the error
      result2 = with_graphql_vcr('error_handling') do
        executor.execute(query)
      end

      # Both should have errors
      assert_graphql_errors(result1)
      assert_graphql_errors(result2)

      # Errors should be identical
      expect(result1['errors']).to eq(result2['errors'])
    end
  end

  describe 'performance tracking with VCR' do
    it 'maintains performance characteristics across recordings' do
      complex_query = <<~GRAPHQL
        {
          #{50.times.map { |i| "field#{i}: fetchData(query: \"perf_test_#{i % 10}\") { result }" }.join("\n")}
        }
      GRAPHQL

      # Measure performance with recording
      time_with_recording = Benchmark.realtime do
        with_graphql_vcr('performance_test', record: :new_episodes) do
          result = executor.execute(complex_query)
          assert_graphql_success(result)
        end
      end

      # Measure performance with playback
      time_with_playback = Benchmark.realtime do
        with_graphql_vcr('performance_test', record: :none) do
          result = executor.execute(complex_query)
          assert_graphql_success(result)
        end
      end

      # Playback should be significantly faster than recording
      expect(time_with_playback).to be < (time_with_recording * 0.5)
    end
  end
end
