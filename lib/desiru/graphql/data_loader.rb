# frozen_string_literal: true

module Desiru
  module GraphQL
    # DataLoader pattern implementation for batching Desiru module calls
    # Prevents N+1 query problems when multiple GraphQL fields request similar data
    class DataLoader
      def initialize
        @loaders = {}
        @results_cache = {}
        @pending_loads = Hash.new { |h, k| h[k] = [] }
      end

      # Get or create a loader for a specific module
      def for(module_class, **options)
        key = loader_key(module_class, options)
        @loaders[key] ||= BatchLoader.new(module_class, **options)
      end

      # Execute all pending loads in batch
      def perform_loads
        @pending_loads.each do |loader_key, batch|
          next if batch.empty?

          loader = @loaders[loader_key]
          results = loader.load_batch(batch.map(&:first))

          batch.each_with_index do |(_inputs, promise), idx|
            promise.fulfill(results[idx])
          end
        end

        @pending_loads.clear
      end

      # Clear all caches
      def clear!
        @results_cache.clear
        @pending_loads.clear
        @loaders.values.each(&:clear_cache!)
      end

      private

      def loader_key(module_class, options)
        "#{module_class.name}:#{options.hash}"
      end

      # Individual batch loader for a specific module
      class BatchLoader
        attr_reader :module_class, :batch_size, :cache

        def initialize(module_class, batch_size: 100, cache: true)
          @module_class = module_class
          @batch_size = batch_size
          @cache = cache
          @cache_store = {} if cache
        end

        # Load a batch of inputs
        def load_batch(inputs_array)
          return load_from_cache(inputs_array) if cache && all_cached?(inputs_array)

          # Group inputs by signature to optimize processing
          grouped = group_by_signature(inputs_array)
          results = []

          grouped.each do |_signature_key, inputs_group|
            module_instance = create_module_instance(inputs_group.first)

            # Process in chunks to respect batch_size
            inputs_group.each_slice(batch_size) do |chunk|
              chunk_results = process_chunk(module_instance, chunk)
              results.concat(chunk_results)

              # Cache results if enabled
              cache_results(chunk, chunk_results) if cache
            end
          end

          results
        end

        # Load a single input (returns a promise for lazy evaluation)
        def load(inputs)
          Promise.new do |promise|
            if cache && @cache_store.key?(cache_key(inputs))
              promise.fulfill(@cache_store[cache_key(inputs)])
            else
              # Queue for batch loading
              queue_for_loading(inputs, promise)
            end
          end
        end

        def clear_cache!
          @cache_store.clear if cache
        end

        private

        def all_cached?(inputs_array)
          inputs_array.all? { |inputs| @cache_store.key?(cache_key(inputs)) }
        end

        def load_from_cache(inputs_array)
          inputs_array.map { |inputs| @cache_store[cache_key(inputs)] }
        end

        def cache_results(inputs_array, results)
          inputs_array.each_with_index do |inputs, idx|
            @cache_store[cache_key(inputs)] = results[idx]
          end
        end

        def cache_key(inputs)
          inputs.sort.to_h.hash
        end

        def group_by_signature(inputs_array)
          inputs_array.group_by do |inputs|
            # Group by input keys to process similar queries together
            inputs.keys.sort.join(':')
          end
        end

        def create_module_instance(sample_inputs)
          # Infer signature from inputs
          signature = infer_signature(sample_inputs)
          module_class.new(signature)
        end

        def infer_signature(inputs)
          # Create a signature based on input structure
          input_fields = inputs.map { |k, v| "#{k}: #{type_for_value(v)}" }.join(', ')
          output_fields = "result: hash" # Default output, can be customized
          "#{input_fields} -> #{output_fields}"
        end

        def type_for_value(value)
          case value
          when String then 'string'
          when Integer then 'int'
          when Float then 'float'
          when TrueClass, FalseClass then 'bool'
          when Array then 'list'
          when Hash then 'hash'
          else 'string'
          end
        end

        def process_chunk(module_instance, chunk)
          if module_instance.respond_to?(:batch_forward)
            # If module supports batch processing
            module_instance.batch_forward(chunk)
          else
            # Fall back to individual processing
            chunk.map { |inputs| module_instance.call(inputs) }
          end
        end

        def queue_for_loading(inputs, promise)
          # This would integrate with the parent DataLoader's pending loads
          # For now, process immediately
          result = module_class.new(infer_signature(inputs)).call(inputs)
          promise.fulfill(result)
          @cache_store[cache_key(inputs)] = result if cache
        end
      end

      # Promise implementation for lazy loading
      class Promise
        def initialize(&block)
          @fulfilled = false
          @value = nil
          @callbacks = []
          block.call(self) if block
        end

        def fulfill(value)
          return if @fulfilled

          @value = value
          @fulfilled = true
          @callbacks.each { |cb| cb.call(value) }
          @callbacks.clear
        end

        def then(&block)
          if @fulfilled
            block.call(@value)
          else
            @callbacks << block
          end
          self
        end

        def value
          raise "Promise not yet fulfilled" unless @fulfilled

          @value
        end

        def fulfilled?
          @fulfilled
        end
      end
    end
  end
end
