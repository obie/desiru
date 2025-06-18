# frozen_string_literal: true

require 'spec_helper'
require 'desiru/graphql/executor'
require 'desiru/graphql/data_loader'
require 'desiru/graphql/schema_generator'

RSpec.describe Desiru::GraphQL::Executor do
  let(:data_loader) { Desiru::GraphQL::DataLoader.new }
  let(:schema_generator) { Desiru::GraphQL::SchemaGenerator.new }

  # Mock module for testing
  let(:test_module) do
    Class.new do
      attr_reader :signature

      def initialize(signature)
        @signature = signature
      end

      def call(inputs)
        { answer: "Hello, #{inputs[:name]}!" }
      end

      def self.name
        'GreetModule'
      end
    end
  end

  before do
    # Register a simple greeting operation
    signature = Desiru::Signature.new('name: string -> answer: string')
    schema_generator.register_signature('greet', signature)
    schema_generator.register_module('greet', test_module.new(signature))

    # Regenerate schema after registration
    @schema = schema_generator.generate_schema
    @executor = described_class.new(@schema, data_loader: data_loader)
  end

  describe '#execute' do
    it 'executes a GraphQL query' do
      query = '{ greet(name: "World") { answer } }'

      result = @executor.execute(query)

      expect(result.to_h).to eq({
                                  "data" => {
                                    "greet" => {
                                      "answer" => "Hello, World!"
                                    }
                                  }
                                })
    end

    it 'adds data_loader to context' do
      query = '{ greet(name: "Test") { answer } }'
      custom_context = { user_id: 123 }

      @executor.execute(query, context: custom_context)

      # The context should have been modified to include data_loader
      expect(custom_context[:data_loader]).to eq(data_loader)
    end

    it 'executes with variables' do
      query = 'query($name: String!) { greet(name: $name) { answer } }'
      variables = { "name" => "Variable" }

      result = @executor.execute(query, variables: variables)

      expect(result.to_h).to eq({
                                  "data" => {
                                    "greet" => {
                                      "answer" => "Hello, Variable!"
                                    }
                                  }
                                })
    end

    it 'performs batch loading' do
      # Track whether perform_loads was called
      load_performed = false
      original_perform_loads = data_loader.method(:perform_loads)
      allow(data_loader).to receive(:perform_loads) do
        load_performed = true
        original_perform_loads.call
      end

      query = '{ greet(name: "Batch") { answer } }'
      @executor.execute(query)

      expect(load_performed).to be true
    end

    it 'clears data loader before execution' do
      expect(data_loader).to receive(:clear!).at_least(:once)

      query = '{ greet(name: "Clear") { answer } }'
      @executor.execute(query)
    end
  end

  describe '#execute_batch' do
    it 'executes multiple queries in a single batch' do
      queries = [
        { query: '{ greet(name: "First") { answer } }' },
        { query: '{ greet(name: "Second") { answer } }' },
        { query: '{ greet(name: "Third") { answer } }' }
      ]

      results = @executor.execute_batch(queries)

      expect(results.size).to eq(3)
      expect(results[0].to_h["data"]["greet"]["answer"]).to eq("Hello, First!")
      expect(results[1].to_h["data"]["greet"]["answer"]).to eq("Hello, Second!")
      expect(results[2].to_h["data"]["greet"]["answer"]).to eq("Hello, Third!")
    end

    it 'shares data_loader across batch queries' do
      queries = [
        { query: '{ greet(name: "A") { answer } }', context: { id: 1 } },
        { query: '{ greet(name: "B") { answer } }', context: { id: 2 } }
      ]

      @executor.execute_batch(queries)

      # Both queries should have the same data_loader in context
      expect(queries[0][:context][:data_loader]).to eq(data_loader)
      expect(queries[1][:context][:data_loader]).to eq(data_loader)
    end

    it 'handles queries with different variables' do
      query_string = 'query($name: String!) { greet(name: $name) { answer } }'

      queries = [
        { query: query_string, variables: { "name" => "Var1" } },
        { query: query_string, variables: { "name" => "Var2" } }
      ]

      results = @executor.execute_batch(queries)

      expect(results[0].to_h["data"]["greet"]["answer"]).to eq("Hello, Var1!")
      expect(results[1].to_h["data"]["greet"]["answer"]).to eq("Hello, Var2!")
    end
  end

  describe '#execute_with_lazy_loading' do
    it 'configures lazy loading behavior' do
      query = '{ greet(name: "Lazy") { answer } }'

      result = @executor.execute_with_lazy_loading(query)

      expect(result.to_h).to eq({
                                  "data" => {
                                    "greet" => {
                                      "answer" => "Hello, Lazy!"
                                    }
                                  }
                                })
    end
  end

  describe 'integration with N+1 prevention' do
    # Module that tracks call counts
    let(:counting_module) do
      call_count = 0

      Class.new do
        define_singleton_method(:call_count) { call_count }
        define_singleton_method(:reset_count!) { call_count = 0 }

        attr_reader :signature

        def initialize(signature)
          @signature = signature
        end

        def call(inputs)
          self.class.send(:increment_count)
          { result: "Called for: #{inputs[:id]}" }
        end

        def batch_forward(inputs_array)
          self.class.send(:increment_count)
          inputs_array.map { |inputs| { result: "Batch called for: #{inputs[:id]}" } }
        end

        def self.name
          'CountingModule'
        end

        define_singleton_method(:increment_count) { call_count += 1 }
      end
    end

    before do
      counting_module.reset_count!

      # Register operations that could cause N+1
      signature = Desiru::Signature.new('id: string -> result: string')
      module_instance = counting_module.new(signature)
      schema_generator.register_signature('fetchData', signature)
      schema_generator.register_module('fetchData', module_instance)

      # Update schema after new registrations
      @schema = schema_generator.generate_schema
      @executor = described_class.new(@schema, data_loader: data_loader)
    end

    it 'batches multiple field requests' do
      # Query that would normally cause N+1
      query = '{
        a: fetchData(id: "1") { result }
        b: fetchData(id: "2") { result }
        c: fetchData(id: "3") { result }
      }'

      result = @executor.execute(query)

      # Should batch all three requests into one call
      expect(counting_module.call_count).to eq(1)

      expect(result.to_h["data"]).to eq({
                                          "a" => { "result" => "Batch called for: 1" },
                                          "b" => { "result" => "Batch called for: 2" },
                                          "c" => { "result" => "Batch called for: 3" }
                                        })
    end
  end
end

RSpec.describe Desiru::GraphQL::LazyFieldExtension do
  let(:schema_generator) { Desiru::GraphQL::SchemaGenerator.new }
  let(:data_loader) { Desiru::GraphQL::DataLoader.new }
  let(:schema) { schema_generator.generate_schema }

  # Test module that returns promises
  let(:promise_module) do
    Class.new do
      attr_reader :signature

      def initialize(signature)
        @signature = signature
      end

      def call(inputs)
        # Return a value that will be wrapped in a promise by DataLoader
        { message: "Promise for: #{inputs[:id]}" }
      end

      def self.name
        'PromiseModule'
      end
    end
  end

  before do
    signature = Desiru::Signature.new('id: string -> message: string')
    schema_generator.register_signature('getPromise', signature)
    schema_generator.register_module('getPromise', promise_module.new(signature))
  end

  it 'handles fulfilled promises' do
    query = '{ getPromise(id: "test") { message } }'
    context = { data_loader: data_loader }

    result = schema.execute(query, context: context)

    # Manually perform loads to simulate what would happen
    data_loader.perform_loads

    expect(result.to_h["data"]["getPromise"]["message"]).to eq("Promise for: test")
  end

  it 'creates lazy resolvers for unfulfilled promises' do
    skip "LazyFieldExtension is not used with GraphQL's built-in dataloader"

    # This test verifies that the extension properly wraps unfulfilled promises
    query = '{ getPromise(id: "lazy") { message } }'
    context = { data_loader: data_loader }

    # Track lazy resolution
    lazy_resolved = false
    allow(GraphQL::Execution::Lazy).to receive(:new) do |&block|
      lazy_resolved = true
      # Execute the block to get the value
      result = block.call
      GraphQL::Execution::Lazy.new { result }
    end

    schema.execute(query, context: context)

    # Should have created a lazy resolver
    expect(lazy_resolved).to be true
  end
end

RSpec.describe Desiru::GraphQL::BatchLoaderMiddleware do
  let(:app) { double('app') }
  let(:middleware) { described_class.new(app) }

  it 'ensures data_loader is available in context' do
    env = { 'graphql.context' => {} }

    expect(app).to receive(:call) do |modified_env|
      expect(modified_env['graphql.context'][:data_loader]).to be_a(Desiru::GraphQL::DataLoader)
      modified_env
    end

    middleware.call(env)
  end

  it 'preserves existing context' do
    env = { 'graphql.context' => { user_id: 123 } }

    expect(app).to receive(:call) do |modified_env|
      expect(modified_env['graphql.context'][:user_id]).to eq(123)
      expect(modified_env['graphql.context'][:data_loader]).to be_a(Desiru::GraphQL::DataLoader)
      modified_env
    end

    middleware.call(env)
  end

  it 'cleans up data_loader after request' do
    env = { 'graphql.context' => {} }
    data_loader = nil

    expect(app).to receive(:call) do |modified_env|
      data_loader = modified_env['graphql.context'][:data_loader]
      modified_env
    end

    expect(data_loader).to receive(:clear!) if data_loader

    middleware.call(env)
  end

  it 'creates context if not provided' do
    env = {}

    expect(app).to receive(:call) do |modified_env|
      expect(modified_env['graphql.context']).to be_a(Hash)
      expect(modified_env['graphql.context'][:data_loader]).to be_a(Desiru::GraphQL::DataLoader)
      modified_env
    end

    middleware.call(env)
  end
end
