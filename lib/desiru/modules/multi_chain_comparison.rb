# frozen_string_literal: true

module Desiru
  module Modules
    # MultiChainComparison module that generates multiple chain-of-thought
    # reasoning paths and compares them to produce the best answer
    class MultiChainComparison < Desiru::Module
      DEFAULT_SIGNATURE = 'question: string -> answer: string, reasoning: string'

      def initialize(signature = nil, model: nil, **kwargs)
        # Extract our specific options before passing to parent
        @num_chains = kwargs.delete(:num_chains) || 3
        @comparison_strategy = kwargs.delete(:comparison_strategy) || :vote
        @temperature = kwargs.delete(:temperature) || 0.7

        # Use default signature if none provided
        signature ||= DEFAULT_SIGNATURE

        # Pass remaining kwargs to parent (config, demos, metadata)
        super
      end

      def forward(**inputs)
        # Handle edge case of zero chains
        return {} if @num_chains <= 0

        # Generate multiple reasoning chains
        chains = generate_chains(inputs)

        # Compare chains to determine best answer
        best_result = case @comparison_strategy
                      when :vote
                        vote_on_chains(chains)
                      when :llm_judge
                        llm_judge_chains(chains, inputs)
                      when :confidence
                        select_by_confidence(chains)
                      else
                        chains.first || {} # Fallback to first chain or empty hash
                      end

        # Ensure best_result is not nil
        best_result ||= {}

        # Include comparison metadata if requested
        if signature.output_fields.key?('comparison_data') || signature.output_fields.key?(:comparison_data)
          best_result[:comparison_data] = {
            num_chains: chains.length,
            strategy: @comparison_strategy,
            all_chains: chains.map { |c| c[:reasoning] }
          }
        end

        best_result
      end

      private

      def generate_chains(inputs)
        chains = []

        @num_chains.times do |i|
          chain_prompt = build_chain_prompt(inputs, i)

          response = model.complete(
            messages: [{ role: 'user', content: chain_prompt }],
            temperature: @temperature
          )

          chain_result = parse_chain_response(response[:content])
          chains << chain_result
        end

        chains
      end

      def build_chain_prompt(inputs, chain_index)
        prompt = "Please solve this problem step by step (Approach #{chain_index + 1}):\n\n"

        # Add inputs
        inputs.each do |key, value|
          prompt += "#{key}: #{value}\n"
        end

        prompt += "\nProvide your reasoning step by step, then give your final answer.\n"
        prompt += "Format your response as:\n"
        prompt += "REASONING: [Your step-by-step reasoning]\n"
        prompt += "ANSWER: [Your final answer]\n"

        # Add output field descriptions
        if signature.output_fields.any?
          prompt += "\nMake sure your answer includes:\n"
          signature.output_fields.each do |name, field|
            next if %w[reasoning comparison_data].include?(name.to_s)

            prompt += "- #{name}: #{field.description || field.type}\n"
          end
        end

        prompt
      end

      def parse_chain_response(response)
        result = {}

        # Extract reasoning
        reasoning_match = response.match(/REASONING:\s*(.+?)(?=ANSWER:|$)/mi)
        result[:reasoning] = reasoning_match ? reasoning_match[1].strip : response

        # Extract answer
        answer_match = response.match(/ANSWER:\s*(.+)/mi)

        if answer_match
          answer_text = answer_match[1].strip

          # Try to parse structured answer
          if answer_text.include?(':') || answer_text.include?('{')
            result.merge!(parse_structured_answer(answer_text))
          elsif !answer_text.empty?
            # Single value answer
            main_output_field = signature.output_fields.keys.map(&:to_sym).find do |k|
              !%i[reasoning comparison_data].include?(k)
            end
            result[main_output_field] = answer_text if main_output_field
          end
        else
          # No ANSWER: section found - check if we should extract from reasoning
          signature.output_fields.keys.map(&:to_sym).find do |k|
            !%i[reasoning comparison_data].include?(k)
          end
          # Don't set the field if there's no clear answer
          # result[main_output_field] = nil if main_output_field
        end

        # Parse any additional fields that might be in the response
        response.scan(/(\w+):\s*([^\n]+)/).each do |key, value|
          key_sym = key.downcase.to_sym
          result[key_sym] = value.strip if signature.output_fields.key?(key_sym) && !result.key?(key_sym)
        end

        result
      end

      def parse_structured_answer(answer_text)
        parsed = {}

        # Try to parse as key-value pairs
        answer_text.scan(/(\w+):\s*([^\n,}]+)/).each do |key, value|
          key_sym = key.downcase.to_sym
          if signature.output_fields.key?(key_sym) || signature.output_fields.key?(key.downcase)
            parsed[key_sym] =
              value.strip
          end
        end

        parsed
      end

      def vote_on_chains(chains)
        return {} if chains.empty?

        # Count votes for each unique answer
        votes = Hash.new(0)
        answer_to_chain = {}

        chains.each do |chain|
          # Get the main answer field (first non-metadata field)
          answer_key = signature.output_fields.keys.map(&:to_sym).find do |k|
            !%i[reasoning comparison_data].include?(k)
          end
          answer_value = chain[answer_key]

          if answer_value && !answer_value.to_s.empty?
            votes[answer_value] += 1
            answer_to_chain[answer_value] ||= chain
          end
        end

        # Return the chain with the most common answer
        if votes.empty?
          chains.first || {}
        else
          winning_answer = votes.max_by { |_, count| count }.first
          answer_to_chain[winning_answer] || chains.first || {}
        end
      end

      def llm_judge_chains(chains, original_inputs)
        judge_prompt = "Given the following problem and multiple solution attempts, select the best answer:\n\n"

        # Add original inputs
        judge_prompt += "Original Problem:\n"
        original_inputs.each do |key, value|
          judge_prompt += "#{key}: #{value}\n"
        end

        # Add all chains
        judge_prompt += "\nSolution Attempts:\n"
        chains.each_with_index do |chain, i|
          judge_prompt += "\n--- Attempt #{i + 1} ---\n"
          judge_prompt += "Reasoning: #{chain[:reasoning]}\n"

          answer_key = signature.output_fields.keys.map(&:to_sym).find do |k|
            !%i[reasoning comparison_data].include?(k)
          end
          judge_prompt += "Answer: #{chain[answer_key]}\n" if chain[answer_key]
        end

        judge_prompt += "\nSelect the best attempt (1-#{chains.length}) and explain why:"

        response = model.complete(
          messages: [{ role: 'user', content: judge_prompt }],
          temperature: 0.1 # Low temperature for more consistent judgment
        )

        # Extract selected chain index
        selection_match = response[:content].match(/(?:attempt|option|choice)\s*#?(\d+)/i)
        selected_index = selection_match ? selection_match[1].to_i - 1 : 0
        selected_index = selected_index.clamp(0, chains.length - 1)

        chains[selected_index]
      end

      def select_by_confidence(chains)
        # Ask model to rate confidence for each chain
        chains_with_confidence = chains.map do |chain|
          confidence_prompt = "Rate your confidence (0-100) in this reasoning and answer:\n"
          confidence_prompt += "Reasoning: #{chain[:reasoning]}\n"

          answer_key = signature.output_fields.keys.map(&:to_sym).find do |k|
            !%i[reasoning comparison_data].include?(k)
          end
          confidence_prompt += "Answer: #{chain[answer_key]}\n" if chain[answer_key]

          confidence_prompt += "\nRespond with just a number between 0 and 100:"

          response = model.complete(
            messages: [{ role: 'user', content: confidence_prompt }],
            temperature: 0.1
          )

          confidence = response[:content].scan(/\d+/).first&.to_i || 50
          chain.merge(confidence: confidence)
        end

        # Select chain with highest confidence
        chains_with_confidence.max_by { |c| c[:confidence] }
      end
    end
  end
end

# Register in the main module namespace for convenience
module Desiru
  MultiChainComparison = Modules::MultiChainComparison
end
