# frozen_string_literal: true

module Desiru
  module Modules
    # Function-style module for majority voting
    # Returns the most common response from multiple completions
    def self.majority(module_instance, **inputs)
      raise ArgumentError, "First argument must be a Desiru module instance" unless module_instance.respond_to?(:call)

      # Number of completions to generate
      num_completions = inputs.delete(:num_completions) || 5

      # Generate multiple completions
      results = []
      num_completions.times do
        result = module_instance.call(**inputs)
        results << result
      end

      # Find the majority answer
      # For simplicity, we'll compare the first output field
      output_fields = module_instance.signature.output_fields.keys
      main_field = output_fields.first

      # Count occurrences of each answer
      answer_counts = Hash.new(0)
      answer_to_result = {}

      results.each do |result|
        answer = result[main_field]
        answer_counts[answer] += 1
        answer_to_result[answer] ||= result
      end

      # Return the result with the most common answer
      majority_answer = answer_counts.max_by { |_, count| count }&.first
      winning_result = answer_to_result[majority_answer] || results.first

      # Add voting metadata if requested
      if output_fields.include?(:voting_data)
        winning_result[:voting_data] = {
          votes: answer_counts,
          num_completions: num_completions,
          consensus_rate: answer_counts[majority_answer].to_f / num_completions
        }
      end

      winning_result
    end
  end
end
