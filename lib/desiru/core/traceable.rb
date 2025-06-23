# frozen_string_literal: true

module Desiru
  module Core
    module Traceable
      def call(inputs = {})
        return super unless trace_enabled?

        # Handle anonymous classes
        class_name = self.class.name || "AnonymousModule"
        module_name = class_name.split('::').last

        Core.trace_context.start_trace(
          module_name: module_name,
          signature: signature,
          inputs: inputs
        )

        begin
          result = super

          outputs = if result.is_a?(ModuleResult)
                      result.outputs
                    else
                      result
                    end

          metadata = if result.is_a?(ModuleResult)
                       result.metadata
                     else
                       {}
                     end

          Core.trace_context.end_trace(
            outputs: outputs,
            metadata: metadata
          )

          result
        rescue StandardError => e
          Core.trace_context.record_error(e)
          raise
        end
      end

      def trace_enabled?
        return true unless defined?(@trace_enabled)

        @trace_enabled
      end

      def enable_trace!
        @trace_enabled = true
      end

      def disable_trace!
        @trace_enabled = false
      end
    end
  end
end
