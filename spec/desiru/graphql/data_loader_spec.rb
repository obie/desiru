# frozen_string_literal: true

require 'spec_helper'
require 'desiru/graphql/data_loader'

RSpec.describe Desiru::GraphQL::DataLoader do
  subject(:data_loader) { described_class.new }

  # Mock module class for testing
  let(:test_module) do
    Class.new do
      attr_reader :signature

      def initialize(signature)
        @signature = signature
      end

      def call(inputs)
        { result: "Processed: #{inputs[:input]}" }
      end

      def self.name
        'TestModule'
      end
    end
  end

  # Module with batch support
  let(:batch_module) do
    Class.new do
      attr_reader :signature

      def initialize(signature)
        @signature = signature
      end

      def batch_forward(inputs_array)
        inputs_array.map { |inputs| { result: "Batch: #{inputs[:input]}" } }
      end

      def call(inputs)
        { result: "Single: #{inputs[:input]}" }
      end

      def self.name
        'BatchModule'
      end
    end
  end

  describe '#for' do
    it 'returns a BatchLoader for a module' do
      loader = data_loader.for(test_module)
      expect(loader).to be_a(Desiru::GraphQL::DataLoader::BatchLoader)
    end

    it 'returns the same loader for same module and options' do
      loader1 = data_loader.for(test_module, batch_size: 10)
      loader2 = data_loader.for(test_module, batch_size: 10)
      expect(loader1).to eq(loader2)
    end

    it 'returns different loaders for different options' do
      loader1 = data_loader.for(test_module, batch_size: 10)
      loader2 = data_loader.for(test_module, batch_size: 20)
      expect(loader1).not_to eq(loader2)
    end
  end

  describe '#perform_loads' do
    it 'processes all pending loads in batch' do
      loader = data_loader.for(test_module)

      promises = []
      3.times do |i|
        promises << loader.load({ input: "test#{i}" })
      end

      # Loads should be queued, not yet fulfilled
      expect(promises.all? { |p| !p.fulfilled? }).to be true

      # Perform batch loading
      data_loader.perform_loads

      # All promises should now be fulfilled
      expect(promises.all?(&:fulfilled?)).to be true
      expect(promises[0].value).to eq({ result: "Processed: test0" })
      expect(promises[1].value).to eq({ result: "Processed: test1" })
      expect(promises[2].value).to eq({ result: "Processed: test2" })
    end

    it 'groups inputs by signature for efficient processing' do
      loader = data_loader.for(test_module)

      # Load with different input structures
      promise1 = loader.load({ input: "a", extra: 1 })
      promise2 = loader.load({ input: "b", extra: 2 })
      promise3 = loader.load({ other: "c" })

      data_loader.perform_loads

      expect(promise1.fulfilled?).to be true
      expect(promise2.fulfilled?).to be true
      expect(promise3.fulfilled?).to be true
    end

    it 'respects batch_size limits' do
      loader = data_loader.for(test_module, batch_size: 2)

      # Queue more items than batch_size
      promises = 5.times.map { |i| loader.load({ input: "test#{i}" }) }

      data_loader.perform_loads

      # All should still be processed correctly
      expect(promises.all?(&:fulfilled?)).to be true
    end

    it 'handles errors gracefully' do
      error_module = Class.new(test_module) do
        def call(_inputs)
          raise "Processing error"
        end
      end

      loader = data_loader.for(error_module)
      promise = loader.load({ input: "test" })

      data_loader.perform_loads

      expect(promise.rejected?).to be true
      expect { promise.value }.to raise_error("Processing error")
    end
  end

  describe '#clear!' do
    it 'clears all caches and pending loads' do
      loader = data_loader.for(test_module, cache: true)

      # Create some cached data
      loader.load({ input: "test" })
      data_loader.perform_loads

      # Queue a new load
      loader.load({ input: "test2" })

      # Clear everything
      data_loader.clear!

      # The pending load should be cleared
      pending_loads = data_loader.instance_variable_get(:@pending_loads)
      expect(pending_loads).to be_empty
    end
  end

  describe 'BatchLoader' do
    let(:loader) { data_loader.for(test_module) }

    describe '#load' do
      it 'returns a promise' do
        promise = loader.load({ input: "test" })
        expect(promise).to be_a(Desiru::GraphQL::DataLoader::Promise)
      end

      it 'queues the load for batch processing' do
        promise = loader.load({ input: "test" })
        expect(promise.fulfilled?).to be false

        data_loader.perform_loads
        expect(promise.fulfilled?).to be true
      end

      context 'with caching enabled' do
        let(:loader) { data_loader.for(test_module, cache: true) }

        it 'returns cached results on subsequent loads' do
          promise1 = loader.load({ input: "test" })
          data_loader.perform_loads
          result1 = promise1.value

          # Second load should use cache
          promise2 = loader.load({ input: "test" })
          expect(promise2.fulfilled?).to be true
          expect(promise2.value).to eq(result1)
        end
      end

      context 'with caching disabled' do
        let(:loader) { data_loader.for(test_module, cache: false) }

        it 'does not cache results' do
          loader.load({ input: "test" })
          data_loader.perform_loads

          # Second load should not use cache
          promise2 = loader.load({ input: "test" })
          expect(promise2.fulfilled?).to be false
        end
      end
    end

    describe '#process_batch' do
      context 'with batch-aware module' do
        let(:loader) { data_loader.for(batch_module) }

        it 'uses batch_forward when available' do
          results = loader.process_batch([{ input: "a" }, { input: "b" }])
          expect(results).to eq([
                                  { result: "Batch: a" },
                                  { result: "Batch: b" }
                                ])
        end
      end

      context 'with regular module' do
        it 'falls back to individual processing' do
          results = loader.process_batch([{ input: "a" }, { input: "b" }])
          expect(results).to eq([
                                  { result: "Processed: a" },
                                  { result: "Processed: b" }
                                ])
        end
      end
    end
  end

  describe 'Promise' do
    describe '#fulfill' do
      it 'fulfills the promise with a value' do
        promise = Desiru::GraphQL::DataLoader::Promise.new
        promise.fulfill("test value")

        expect(promise.fulfilled?).to be true
        expect(promise.value).to eq("test value")
      end

      it 'only fulfills once' do
        promise = Desiru::GraphQL::DataLoader::Promise.new
        promise.fulfill("first")
        promise.fulfill("second")

        expect(promise.value).to eq("first")
      end

      it 'executes callbacks' do
        promise = Desiru::GraphQL::DataLoader::Promise.new
        callback_value = nil

        promise.then { |value| callback_value = value }
        promise.fulfill("test")

        expect(callback_value).to eq("test")
      end
    end

    describe '#reject' do
      it 'rejects the promise with an error' do
        promise = Desiru::GraphQL::DataLoader::Promise.new
        error = StandardError.new("test error")
        promise.reject(error)

        expect(promise.rejected?).to eq(true)
        expect { promise.value }.to raise_error(StandardError, "test error")
      end
    end

    describe '#then' do
      it 'executes callback immediately if already fulfilled' do
        promise = Desiru::GraphQL::DataLoader::Promise.new
        promise.fulfill("test")

        callback_value = nil
        promise.then { |value| callback_value = value }

        expect(callback_value).to eq("test")
      end

      it 'queues callback if not yet fulfilled' do
        promise = Desiru::GraphQL::DataLoader::Promise.new
        callback_value = nil

        promise.then { |value| callback_value = value }
        expect(callback_value).to be_nil

        promise.fulfill("test")
        expect(callback_value).to eq("test")
      end
    end

    describe '#value' do
      it 'waits for fulfillment' do
        promise = Desiru::GraphQL::DataLoader::Promise.new

        Thread.new do
          sleep 0.1
          promise.fulfill("delayed value")
        end

        value = promise.value
        expect(value).to eq("delayed value")
      end

      it 'supports timeout' do
        promise = Desiru::GraphQL::DataLoader::Promise.new

        expect { promise.value(timeout: 0.1) }.to raise_error("Promise not yet fulfilled")
      end
    end

    describe 'thread safety' do
      it 'handles concurrent fulfillment attempts' do
        promise = Desiru::GraphQL::DataLoader::Promise.new
        results = []

        threads = 10.times.map do |i|
          Thread.new do
            promise.fulfill("value #{i}")
            results << promise.value
          end
        end

        threads.each(&:join)

        # All threads should see the same value
        expect(results.uniq.size).to eq(1)
      end

      it 'handles concurrent callbacks' do
        promise = Desiru::GraphQL::DataLoader::Promise.new
        callback_count = 0
        mutex = Mutex.new

        threads = 10.times.map do
          Thread.new do
            promise.then do |_value|
              mutex.synchronize { callback_count += 1 }
            end
          end
        end

        threads.each(&:join)
        promise.fulfill("test")

        # Allow callbacks to complete
        sleep 0.1

        expect(callback_count).to eq(10)
      end
    end
  end

  describe 'request deduplication' do
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
          { result: "Called: #{inputs[:input]}" }
        end

        def batch_forward(inputs_array)
          self.class.send(:increment_count)
          inputs_array.map { |inputs| { result: "Batch: #{inputs[:input]}" } }
        end

        def self.name
          'CountingModule'
        end

        define_singleton_method(:increment_count) { call_count += 1 }
      end
    end

    before do
      counting_module.reset_count!
    end

    it 'deduplicates identical requests within the same batch' do
      loader = data_loader.for(counting_module)

      # Load the same input multiple times
      promises = 5.times.map { loader.load({ input: "same" }) }

      # Should all be the same promise object
      expect(promises.uniq.size).to eq(1)

      data_loader.perform_loads

      # Module should only be called once
      expect(counting_module.call_count).to eq(1)

      # All promises should have the same result
      results = promises.map(&:value)
      expect(results.uniq.size).to eq(1)
      expect(results.first).to eq({ result: "Batch: same" })
    end

    it 'processes different requests separately' do
      loader = data_loader.for(counting_module)

      # Load different inputs
      promise1 = loader.load({ input: "a" })
      promise2 = loader.load({ input: "b" })
      promise3 = loader.load({ input: "a" }) # duplicate of first

      # First and third should be the same promise
      expect(promise1).to eq(promise3)
      expect(promise1).not_to eq(promise2)

      data_loader.perform_loads

      # Module should be called once with 2 unique inputs
      expect(counting_module.call_count).to eq(1)

      expect(promise1.value).to eq({ result: "Batch: a" })
      expect(promise2.value).to eq({ result: "Batch: b" })
      expect(promise3.value).to eq({ result: "Batch: a" })
    end

    it 'handles deduplication with cache disabled' do
      loader = data_loader.for(counting_module, cache: false)

      # Load same input multiple times
      promise1 = loader.load({ input: "test" })
      promise2 = loader.load({ input: "test" })

      # Should deduplicate even without cache
      expect(promise1).to eq(promise2)

      data_loader.perform_loads

      # Should only call module once
      expect(counting_module.call_count).to eq(1)
    end

    it 'deduplicates across different key orders' do
      loader = data_loader.for(counting_module)

      # Same data, different key order
      promise1 = loader.load({ a: 1, b: 2 })
      promise2 = loader.load({ b: 2, a: 1 })

      # Should recognize as the same request
      expect(promise1).to eq(promise2)

      data_loader.perform_loads

      expect(counting_module.call_count).to eq(1)
    end

    it 'handles concurrent duplicate requests' do
      loader = data_loader.for(counting_module)
      promises = []
      mutex = Mutex.new

      threads = 10.times.map do
        Thread.new do
          promise = loader.load({ input: "concurrent" })
          mutex.synchronize { promises << promise }
        end
      end

      threads.each(&:join)

      # All should be the same promise
      expect(promises.uniq.size).to eq(1)

      data_loader.perform_loads

      # Module should only be called once
      expect(counting_module.call_count).to eq(1)
    end
  end
end
