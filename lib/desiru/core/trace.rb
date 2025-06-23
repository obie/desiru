# frozen_string_literal: true

module Desiru
  module Core
    class Trace
      attr_reader :module_name, :signature, :inputs, :outputs, :metadata, :timestamp

      def initialize(module_name:, signature:, inputs: {}, outputs: {}, metadata: {})
        @module_name = module_name
        @signature = signature
        @inputs = inputs
        @outputs = outputs
        @metadata = metadata
        @timestamp = Time.now
      end

      def to_h
        {
          module_name: @module_name,
          signature: @signature.is_a?(String) ? @signature : @signature.to_h,
          inputs: @inputs,
          outputs: @outputs,
          metadata: @metadata,
          timestamp: @timestamp
        }
      end

      def to_example
        Example.new(**@inputs, **@outputs)
      end

      def success?
        @metadata[:success] != false
      end

      def error?
        @metadata.key?(:error)
      end

      def error
        @metadata[:error]
      end

      def duration
        @metadata[:duration]
      end

      def duration_ms
        return 0 unless duration

        (duration * 1000).to_f
      end

      def ==(other)
        return false unless other.is_a?(self.class)

        @module_name == other.module_name &&
          @signature == other.signature &&
          @inputs == other.inputs &&
          @outputs == other.outputs &&
          @metadata == other.metadata
      end
    end

    class TraceCollector
      attr_reader :traces

      def initialize
        @traces = []
        @enabled = true
        @filters = []
      end

      def collect(trace)
        return unless @enabled && trace.is_a?(Trace)
        return if @filters.any? { |filter| !filter.call(trace) }

        @traces << trace
      end

      def add_filter(&block)
        @filters << block if block_given?
      end

      def clear_filters
        @filters.clear
      end

      def enable
        @enabled = true
      end

      def disable
        @enabled = false
      end

      def enabled?
        @enabled
      end

      def clear
        @traces.clear
      end

      def size
        @traces.size
      end

      def empty?
        @traces.empty?
      end

      def recent(count = 10)
        @traces.last(count)
      end

      def by_module(module_name)
        @traces.select { |trace| trace.module_name == module_name }
      end

      def successful
        @traces.select(&:success?)
      end

      def failed
        @traces.reject(&:success?)
      end

      def to_examples
        @traces.map(&:to_example)
      end

      def export
        @traces.map(&:to_h)
      end

      def filter_by_module(module_name)
        @traces.select { |trace| trace.module_name == module_name }
      end

      def filter_by_success(success: true)
        if success
          @traces.select(&:success?)
        else
          @traces.reject(&:success?)
        end
      end

      def filter_by_time_range(start_time, end_time)
        @traces.select { |trace| trace.timestamp.between?(start_time, end_time) }
      end

      def statistics
        return default_statistics if @traces.empty?

        total = @traces.size
        successful = @traces.count(&:success?)

        # Group by module
        by_module = @traces.group_by(&:module_name).transform_values do |module_traces|
          durations = module_traces.map(&:duration_ms).compact
          {
            count: module_traces.size,
            avg_duration_ms: durations.empty? ? 0 : durations.sum / durations.size.to_f
          }
        end

        # Calculate average duration
        all_durations = @traces.map(&:duration_ms).compact
        avg_duration = all_durations.empty? ? 0 : all_durations.sum / all_durations.size.to_f

        {
          total_traces: total,
          success_rate: total.positive? ? successful.to_f / total : 0,
          average_duration_ms: avg_duration,
          by_module: by_module
        }
      end

      private

      def default_statistics
        {
          total_traces: 0,
          success_rate: 0,
          average_duration_ms: 0,
          by_module: {}
        }
      end
    end

    class TraceContext
      attr_reader :collector

      def initialize(collector = nil)
        @collector = collector || TraceCollector.new
        @stack = []
      end

      # Class method to temporarily use a specific collector
      def self.with_collector(collector)
        # Save current context if it exists
        previous_context = Thread.current[:desiru_trace_context]

        # Create new context with the provided collector
        context = new(collector)
        Thread.current[:desiru_trace_context] = context

        # Store context for thread propagation
        Thread.current[:desiru_trace_collector_for_threads] = collector

        # Execute the block
        yield
      ensure
        # Restore previous context
        Thread.current[:desiru_trace_context] = previous_context
        Thread.current[:desiru_trace_collector_for_threads] = nil
      end

      # Get the current trace context
      def self.current
        Core.trace_context
      end

      def start_trace(module_name:, signature:, inputs: {})
        trace_data = {
          module_name: module_name,
          signature: signature,
          inputs: inputs,
          start_time: Time.now,
          metadata: {}
        }
        @stack.push(trace_data)
      end

      def add_metadata(metadata)
        return if @stack.empty?

        current_trace = @stack.last
        current_trace[:metadata] = (current_trace[:metadata] || {}).merge(metadata)
      end

      def end_trace(outputs: {}, metadata: {})
        return if @stack.empty?

        trace_data = @stack.pop
        duration = Time.now - trace_data[:start_time]

        # Merge accumulated metadata with end trace metadata
        combined_metadata = (trace_data[:metadata] || {}).merge(metadata).merge(
          duration: duration,
          success: true
        )

        trace = Trace.new(
          module_name: trace_data[:module_name],
          signature: trace_data[:signature],
          inputs: trace_data[:inputs],
          outputs: outputs,
          metadata: combined_metadata
        )

        @collector.collect(trace)
        trace
      end

      def record_error(error, outputs: {}, metadata: {})
        return if @stack.empty?

        trace_data = @stack.pop
        duration = Time.now - trace_data[:start_time]

        # Merge accumulated metadata with error metadata
        combined_metadata = (trace_data[:metadata] || {}).merge(metadata).merge(
          duration: duration,
          success: false,
          error: error.message,
          error_class: error.class.name
        )

        trace = Trace.new(
          module_name: trace_data[:module_name],
          signature: trace_data[:signature],
          inputs: trace_data[:inputs],
          outputs: outputs,
          metadata: combined_metadata
        )

        @collector.collect(trace)
        trace
      end

      def with_trace(module_name:, signature:, inputs: {})
        start_trace(module_name: module_name, signature: signature, inputs: inputs)

        begin
          outputs = yield
          end_trace(outputs: outputs)
          outputs
        rescue StandardError => e
          record_error(e)
          raise
        end
      end
    end

    class << self
      def trace_collector
        @trace_collector ||= TraceCollector.new
      end

      def trace_context
        # Check for thread-local context first (set by with_collector)
        if Thread.current[:desiru_trace_context]
          Thread.current[:desiru_trace_context]
        elsif Thread.current[:desiru_trace_collector_for_threads]
          # Create a new context for this thread using the parent's collector
          Thread.current[:desiru_trace_context] = TraceContext.new(Thread.current[:desiru_trace_collector_for_threads])
        else
          @trace_context ||= TraceContext.new(trace_collector)
        end
      end

      def reset_traces!
        @trace_collector = TraceCollector.new
        @trace_context = TraceContext.new(@trace_collector)
      end
    end
  end
end
