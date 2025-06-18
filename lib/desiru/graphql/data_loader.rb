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
        @pending_promises = Hash.new { |h, k| h[k] = {} }
        @mutex = Mutex.new
      end

      # Get or create a loader for a specific module
      def for(module_class_or_instance, **options)
        # Handle both module classes and instances
        module_class = module_class_or_instance.is_a?(Class) ? module_class_or_instance : module_class_or_instance.class
        key = loader_key(module_class, options)
        @loaders[key] ||= BatchLoader.new(module_class_or_instance, self, **options)
      end

      # Execute all pending loads in batch
      def perform_loads
        @mutex.synchronize do
          @pending_loads.each do |loader_key, batch|
            process_loader_batch(loader_key, batch)
          end

          @pending_loads.clear
          @pending_promises.clear
        end
      end

      # Clear all caches
      def clear!
        @mutex.synchronize do
          @results_cache.clear
          @pending_loads.clear
          @pending_promises.clear
          @loaders.each_value(&:clear_cache!)
        end
      end

      private

      def loader_key(module_class, options)
        "#{module_class.name}:#{options.hash}"
      end

      def group_inputs_by_signature(inputs_array)
        inputs_array.group_by do |inputs|
          # Group by input keys to process similar queries together
          inputs.keys.sort.join(':')
        end
      end

      def process_loader_batch(loader_key, batch)
        return if batch.empty?

        loader = @loaders[loader_key]
        return unless loader # Skip if loader not found

        # Deduplicate requests
        unique_inputs_map, promises_by_inputs = deduplicate_batch(batch)
        unique_inputs = unique_inputs_map.values

        # Process batch and handle results
        results_map = execute_batch(loader, unique_inputs, unique_inputs_map)

        # Fulfill promises with results
        fulfill_promises(promises_by_inputs, results_map)
      end

      def deduplicate_batch(batch)
        unique_inputs_map = {}
        promises_by_inputs = Hash.new { |h, k| h[k] = [] }

        batch.each do |inputs, promise|
          input_key = inputs.sort.to_h.hash
          unique_inputs_map[input_key] = inputs
          promises_by_inputs[input_key] << promise
        end

        [unique_inputs_map, promises_by_inputs]
      end

      def execute_batch(loader, unique_inputs, unique_inputs_map)
        results_map = {}

        begin
          results = loader.load_batch(unique_inputs)
          unique_inputs.each_with_index do |inputs, idx|
            input_key = inputs.sort.to_h.hash
            results_map[input_key] = results[idx]
          end
        rescue StandardError => e
          # Mark all promises as rejected on error
          unique_inputs_map.each_key do |input_key|
            results_map[input_key] = { error: e }
          end
        end

        results_map
      end

      def fulfill_promises(promises_by_inputs, results_map)
        promises_by_inputs.each do |input_key, promises|
          result = results_map[input_key]

          promises.each do |promise|
            if result.is_a?(Hash) && result[:error]
              promise.reject(result[:error])
            else
              promise.fulfill(result)
            end
          end
        end
      end

      # Individual batch loader for a specific module
      class BatchLoader
        attr_reader :module_class_or_instance, :batch_size, :cache, :parent_loader

        def initialize(module_class_or_instance, parent_loader, batch_size: 100, cache: true)
          @module_class_or_instance = module_class_or_instance
          @parent_loader = parent_loader
          @batch_size = batch_size
          @cache = cache
          @cache_store = {} if cache
        end

        # Load a batch of inputs - used for immediate batch processing
        def load_batch(inputs_array)
          return load_from_cache(inputs_array) if cache && all_cached?(inputs_array)

          results = process_batch(inputs_array)

          # Cache results if enabled
          cache_results(inputs_array, results) if cache

          results
        end

        # Load a single input (returns a promise for lazy evaluation)
        def load(inputs)
          # Check cache first if enabled
          if cache && @cache_store.key?(cache_key(inputs))
            # Return immediately fulfilled promise for cached value
            promise = Promise.new
            promise.fulfill(@cache_store[cache_key(inputs)])
            promise
          else
            # Check for existing pending promise to enable deduplication
            existing_promise = check_pending_promise(inputs)
            return existing_promise if existing_promise

            # Create promise and queue for batch loading
            Promise.new do |promise|
              queue_for_loading(inputs, promise)
            end
          end
        end

        def clear_cache!
          @cache_store.clear if cache
        end

        # Process a batch of inputs
        def process_batch(inputs_array)
          # Use the provided module instance or create one
          module_instance = if @module_class_or_instance.is_a?(Class)
                              create_module_instance(inputs_array.first)
                            else
                              @module_class_or_instance
                            end

          if module_instance.respond_to?(:batch_forward)
            # If module supports batch processing
            module_instance.batch_forward(inputs_array)
          else
            # Fall back to individual processing
            inputs_array.map { |inputs| module_instance.call(inputs) }
          end
        end

        # Cache a single result
        def cache_result(inputs, result)
          @cache_store[cache_key(inputs)] = result if cache
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

        def create_module_instance(sample_inputs)
          # Infer signature from inputs
          signature = infer_signature(sample_inputs)

          # Get the module class
          if @module_class_or_instance.is_a?(Class)
            @module_class_or_instance.new(signature)
          else
            # Already an instance, return it
            @module_class_or_instance
          end
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
          else value.class.name.downcase
          end
        end

        def check_pending_promise(inputs)
          # Check if there's already a pending promise for these inputs
          final_key = loader_key
          input_key = inputs.sort.to_h.hash

          parent_loader.instance_variable_get(:@mutex).synchronize do
            parent_loader.instance_variable_get(:@pending_promises)[final_key][input_key]
          end
        end

        def queue_for_loading(inputs, promise)
          # Queue the request with the parent DataLoader for batch processing
          final_key = loader_key
          input_key = inputs.sort.to_h.hash

          parent_loader.instance_variable_get(:@mutex).synchronize do
            # Store this promise for future deduplication
            parent_loader.instance_variable_get(:@pending_promises)[final_key][input_key] = promise
            parent_loader.instance_variable_get(:@pending_loads)[final_key] << [inputs, promise]
          end
        end

        def loader_key
          # Create a key that matches how this loader was registered
          module_name = if @module_class_or_instance.is_a?(Class)
                          @module_class_or_instance.name
                        else
                          @module_class_or_instance.class.name
                        end
          loader_key = "#{module_name}:#{batch_size}:#{cache}"

          # Find the actual loader key that was used to create this loader
          loaders = parent_loader.instance_variable_get(:@loaders)
          actual_key = loaders.keys.find { |k| loaders[k] == self }
          actual_key || loader_key
        end
      end

      # Thread-safe Promise implementation for lazy loading
      class Promise
        def initialize(&block)
          @mutex = Mutex.new
          @condition = ConditionVariable.new
          @fulfilled = false
          @value = nil
          @error = nil
          @callbacks = []
          block&.call(self)
        end

        def fulfill(value)
          callbacks_to_run = nil

          @mutex.synchronize do
            return if @fulfilled

            @value = value
            @fulfilled = true
            callbacks_to_run = @callbacks.dup
            @callbacks.clear

            # Signal all waiting threads
            @condition.broadcast
          end

          # Run callbacks outside the mutex to avoid deadlock
          callbacks_to_run&.each { |cb| cb.call(value) }
        end

        def reject(error)
          @mutex.synchronize do
            return if @fulfilled

            @error = error
            @fulfilled = true
            @callbacks.clear

            # Signal all waiting threads
            @condition.broadcast
          end
        end

        def then(&block)
          run_immediately = false
          value_to_pass = nil

          @mutex.synchronize do
            if @fulfilled && !@error
              run_immediately = true
              value_to_pass = @value
            elsif !@fulfilled
              @callbacks << block
            end
          end

          # Run callback outside mutex if already fulfilled
          block.call(value_to_pass) if run_immediately

          self
        end

        def value(timeout: nil)
          @mutex.synchronize do
            if timeout
              end_time = Time.now + timeout
              until @fulfilled
                remaining = end_time - Time.now
                break if remaining <= 0

                @condition.wait(@mutex, remaining)
              end
            else
              @condition.wait(@mutex) until @fulfilled
            end

            raise @error if @error
            raise "Promise not yet fulfilled" unless @fulfilled

            @value
          end
        end

        def fulfilled?
          @mutex.synchronize { @fulfilled }
        end

        def rejected?
          @mutex.synchronize { @fulfilled && !@error.nil? }
        end
      end
    end
  end
end
