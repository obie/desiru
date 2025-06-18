# frozen_string_literal: true

module Desiru
  module Modules
    # Chain of Thought module - adds reasoning steps before producing outputs
    class ChainOfThought < Predict
      def initialize(signature, **)
        # Extend signature to include reasoning field
        extended_sig = extend_signature_with_reasoning(signature)
        super(extended_sig, **)
        @original_signature = signature
      end

      protected

      def build_system_prompt
        <<~PROMPT
          You are a helpful AI assistant that thinks step by step. You will be given inputs and must produce outputs according to the following specification:

          #{format_original_signature}

          Before providing the final answer, you must show your reasoning process. Think through the problem step by step.

          Format your response as:
          reasoning: [Your step-by-step thought process]
          [output fields]: [Your final answers]

          #{format_descriptions}
        PROMPT
      end

      def build_user_prompt(inputs)
        lines = ['Given the following inputs:']

        inputs.each do |key, value|
          lines << "#{key}: #{format_value(value)}"
        end

        lines << "\nThink step by step and provide:"
        lines << 'reasoning: (your thought process)'

        @original_signature.output_fields.each_key do |key|
          lines << "#{key}: (your answer)"
        end

        lines.join("\n")
      end

      def parse_response(content)
        result = super

        # Extract reasoning if not already captured
        unless result[:reasoning]
          reasoning_match = content.match(/reasoning:\s*(.+?)(?=\n\w+:|$)/mi)
          result[:reasoning] = reasoning_match[1].strip if reasoning_match
        end

        # Ensure we have all original output fields
        @original_signature.output_fields.each_key do |field|
          result[field] ||= result[field.to_s]
        end

        result
      end

      private

      def extend_signature_with_reasoning(signature)
        sig_string = case signature
                     when Signature
                       signature.raw_signature
                     when String
                       signature
                     else
                       raise ModuleError, 'Invalid signature type'
                     end

        # Parse the signature parts
        parts = sig_string.split('->').map(&:strip)
        inputs = parts[0]
        outputs = parts[1]

        # Add reasoning to outputs if not already present
        outputs = "reasoning: string, #{outputs}" unless outputs.include?('reasoning')

        Signature.new("#{inputs} -> #{outputs}")
      end

      def format_original_signature
        case @original_signature
        when Signature
          "#{format_fields(@original_signature.input_fields)} -> #{format_fields(@original_signature.output_fields)}"
        when String
          @original_signature
        else
          signature.raw_signature
        end
      end
    end
  end
end

# Register in the main module namespace for convenience
module Desiru
  ChainOfThought = Modules::ChainOfThought
end
