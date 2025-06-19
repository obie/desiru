# frozen_string_literal: true

module Desiru
  module Optimizers
    # COPRO (Cooperative Prompt Optimization) optimizer
    # Generates and refines instructions for each module using coordinate ascent
    class COPRO < Base
      def initialize(config = {})
        super
        @max_iterations = config[:max_iterations] || 10
        @num_candidates = config[:num_candidates] || 5
        @temperature = config[:temperature] || 0.7
        @improvement_threshold = config[:improvement_threshold] || 0.01
      end

      def compile(program, trainset, valset = nil, **kwargs)
        valset ||= trainset # Use trainset for validation if no valset provided

        # Initialize best score
        best_score = evaluate_program(program, valset, kwargs[:metric])
        best_program = program.dup

        Desiru.logger.info("[COPRO] Initial score: #{best_score}")

        # Iterate through optimization rounds
        @max_iterations.times do |iteration|
          Desiru.logger.info("[COPRO] Starting iteration #{iteration + 1}/#{@max_iterations}")

          # Try to improve each predictor
          improved = false

          program.predictors.each do |name, predictor|
            Desiru.logger.info("[COPRO] Optimizing predictor: #{name}")

            # Generate instruction candidates
            candidates = generate_instruction_candidates(predictor, trainset, name)

            # Evaluate each candidate
            best_candidate_score = best_score
            best_candidate_instruction = nil

            candidates.each do |instruction|
              # Create program with new instruction
              candidate_program = create_program_with_instruction(
                best_program,
                name,
                instruction
              )

              # Evaluate
              score = evaluate_program(candidate_program, valset, kwargs[:metric])

              if score > best_candidate_score
                best_candidate_score = score
                best_candidate_instruction = instruction
              end
            end

            # Update if improved
            next unless best_candidate_instruction && (best_candidate_score - best_score) > @improvement_threshold

            Desiru.logger.info("[COPRO] Improved #{name}: #{best_score} -> #{best_candidate_score}")
            best_program = create_program_with_instruction(
              best_program,
              name,
              best_candidate_instruction
            )
            best_score = best_candidate_score
            improved = true
          end

          # Early stopping if no improvement
          break unless improved
        end

        Desiru.logger.info("[COPRO] Final score: #{best_score}")
        best_program
      end

      private

      def generate_instruction_candidates(predictor, trainset, predictor_name)
        candidates = []

        # Get examples of good performance
        good_examples = select_good_examples(predictor, trainset)

        # Generate initial instruction based on signature
        signature = predictor.signature
        base_instruction = generate_base_instruction(signature, predictor_name)
        candidates << base_instruction

        # Generate variations
        (@num_candidates - 1).times do |i|
          variation_prompt = build_variation_prompt(
            base_instruction,
            signature,
            good_examples,
            i
          )

          response = model.complete(
            messages: [{ role: 'user', content: variation_prompt }],
            temperature: @temperature
          )

          instruction = extract_instruction(response[:content])
          candidates << instruction if instruction
        end

        candidates.compact.uniq
      end

      def generate_base_instruction(signature, predictor_name)
        instruction = "You are solving a #{predictor_name} task.\n\n"

        # Add input description
        if signature.input_fields.any?
          instruction += "Given the following inputs:\n"
          signature.input_fields.each do |name, field|
            instruction += "- #{name}: #{field.description || field.type}\n"
          end
          instruction += "\n"
        end

        # Add output description
        if signature.output_fields.any?
          instruction += "Produce the following outputs:\n"
          signature.output_fields.each do |name, field|
            instruction += "- #{name}: #{field.description || field.type}\n"
          end
        end

        instruction
      end

      def build_variation_prompt(base_instruction, signature, good_examples, variation_index)
        prompt = "Improve the following instruction for better performance:\n\n"
        prompt += "Current instruction:\n#{base_instruction}\n\n"

        # Add task context
        prompt += "Task signature: #{signature}\n\n"

        # Add examples of good performance
        if good_examples.any?
          prompt += "Examples of successful completions:\n"
          good_examples.take(3).each do |example|
            prompt += format_example(example)
          end
        end

        # Request specific type of improvement
        improvement_types = [
          "Make the instruction more specific and detailed",
          "Add helpful constraints or guidelines",
          "Clarify any ambiguous requirements",
          "Add examples or patterns to follow",
          "Emphasize important aspects of the task"
        ]

        prompt += "\n#{improvement_types[variation_index % improvement_types.length]}.\n"
        prompt += "Provide only the improved instruction:"

        prompt
      end

      def select_good_examples(predictor, trainset)
        good_examples = []

        trainset.each do |example|
          # Run predictor on example inputs
          result = predictor.call(example[:inputs])

          # Check if output matches expected
          good_examples << example if outputs_match?(result, example[:outputs])
        rescue StandardError
          # Skip failed examples
        end

        good_examples
      end

      def outputs_match?(actual, expected)
        return false unless actual.is_a?(Hash) && expected.is_a?(Hash)

        expected.all? do |key, expected_value|
          actual_value = actual[key]

          # Flexible matching for different types
          case expected_value
          when String
            actual_value.to_s.strip.downcase == expected_value.strip.downcase
          when Numeric
            (actual_value.to_f - expected_value.to_f).abs < 0.001
          else
            actual_value == expected_value
          end
        end
      end

      def format_example(example)
        formatted = "\nExample:\n"

        if example[:inputs]
          formatted += "Inputs: "
          formatted += example[:inputs].map { |k, v| "#{k}=#{v}" }.join(", ")
          formatted += "\n"
        end

        if example[:outputs]
          formatted += "Outputs: "
          formatted += example[:outputs].map { |k, v| "#{k}=#{v}" }.join(", ")
          formatted += "\n"
        end

        formatted
      end

      def extract_instruction(response)
        # Clean up the response
        instruction = response.strip

        # Remove any meta-commentary
        instruction = instruction.sub(/^(Here's |This is )?the improved instruction:?\s*/i, '')
        instruction = instruction.sub(/^Improved instruction:?\s*/i, '')

        # Remove quotes if wrapped
        instruction.gsub(/^["']|["']$/, '')
      end

      def create_program_with_instruction(program, predictor_name, instruction)
        new_program = program.dup

        # Get the predictor
        predictor = new_program.predictors[predictor_name]
        return new_program unless predictor

        # Create new predictor with updated instruction
        new_predictor = predictor.dup
        new_predictor.instance_variable_set(:@instruction, instruction)

        # Update the program
        new_program.instance_variable_set("@#{predictor_name}", new_predictor)

        new_program
      end

      def evaluate_program(program, dataset, metric)
        scores = []

        dataset.each do |example|
          # Run program
          prediction = program.forward(**example[:inputs])

          # Calculate score
          score = metric.call(prediction, example[:outputs])
          scores << score
        rescue StandardError => e
          Desiru.logger.debug("[COPRO] Evaluation error: #{e.message}")
          scores << 0.0
        end

        # Return average score
        scores.empty? ? 0.0 : scores.sum.to_f / scores.length
      end
    end
  end
end
