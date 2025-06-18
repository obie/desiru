# frozen_string_literal: true

module Desiru
  module Optimizers
    # Bootstrap Few-Shot optimizer - automatically selects effective demonstrations
    class BootstrapFewShot < Base
      def compile(program, trainset:, valset: nil)
        trace_optimization('Starting BootstrapFewShot optimization', {
                             trainset_size: trainset.size,
                             valset_size: valset&.size || 0
                           })

        # Create a working copy of the program
        optimized_program = deep_copy_program(program)

        # Optimize each module in the program
        optimize_modules(optimized_program, trainset, valset)

        # Evaluate final performance
        if valset
          final_score = evaluate(optimized_program, valset)
          trace_optimization('Final validation score', final_score)
        end

        optimized_program
      end

      def optimize_module(module_instance, examples)
        trace_optimization('Optimizing module', {
                             module: module_instance.class.name,
                             examples_available: examples.size
                           })

        # Bootstrap demonstrations
        bootstrapped_demos = bootstrap_demonstrations(module_instance, examples)

        # Select best demonstrations
        selected_demos = select_demonstrations(
          module_instance,
          bootstrapped_demos,
          examples
        )

        # Return module with selected demonstrations
        module_instance.with_demos(selected_demos)
      end

      private

      def deep_copy_program(program)
        # This is a simplified version - in practice, we'd need proper deep copying
        program.class.new(config: program.config, metadata: program.metadata)
      end

      def optimize_modules(program, trainset, _valset)
        # Get all modules from the program
        modules_to_optimize = extract_modules(program)

        modules_to_optimize.each do |module_name, module_instance|
          trace_optimization('Processing module', { name: module_name })

          # Create module-specific examples
          module_examples = create_module_examples(module_instance, trainset)

          # Optimize the module
          optimized_module = optimize_module(module_instance, module_examples)

          # Replace in program
          replace_module(program, module_name, optimized_module)
        end
      end

      def bootstrap_demonstrations(module_instance, examples)
        demonstrations = []
        errors = 0

        examples.each do |example|
          break if demonstrations.size >= config[:max_bootstrapped_demos]
          break if errors >= config[:max_errors]

          begin
            # Get module prediction
            inputs = example.reject { |k, _| %i[answer output].include?(k) }
            prediction = module_instance.call(inputs)

            # Score the prediction
            score = score_prediction(prediction, example)

            if score >= 0.5 # Configurable threshold
              demonstrations << {
                input: format_demo_input(inputs),
                output: format_demo_output(prediction),
                score: score
              }
            else
              errors += 1
            end
          rescue StandardError => e
            trace_optimization('Error during bootstrap', { error: e.message })
            errors += 1
          end
        end

        demonstrations
      end

      def select_demonstrations(_module_instance, bootstrapped, examples)
        all_demos = bootstrapped

        # Add labeled examples if available
        labeled = examples.select { |ex| ex[:answer] || ex[:output] }
        labeled_demos = labeled.first(config[:max_labeled_demos]).map do |ex|
          inputs = ex.reject { |k, _| %i[answer output].include?(k) }
          {
            input: format_demo_input(inputs),
            output: format_demo_output(ex),
            score: 1.0 # Perfect score for labeled examples
          }
        end

        all_demos += labeled_demos

        # Sort by score and diversity
        selected = select_diverse_demos(all_demos)

        # Take top K
        selected.first(config[:max_bootstrapped_demos])
      end

      def select_diverse_demos(demos)
        # Simple diversity selection - could be improved
        selected = []
        remaining = demos.sort_by { |d| -d[:score] }

        while selected.size < config[:max_bootstrapped_demos] && remaining.any?
          # Take the best remaining
          best = remaining.shift
          selected << best

          # Remove similar demos (simple text similarity)
          remaining.reject! do |demo|
            similarity(demo[:input], best[:input]) > 0.8
          end
        end

        selected
      end

      def similarity(text1, text2)
        # Very simple similarity - could use better metrics
        tokens1 = tokenize(text1)
        tokens2 = tokenize(text2)

        return 0.0 if tokens1.empty? || tokens2.empty?

        intersection = (tokens1 & tokens2).size
        union = (tokens1 | tokens2).size

        intersection.to_f / union
      end

      def format_demo_input(inputs)
        inputs.map { |k, v| "#{k}: #{v}" }.join("\n")
      end

      def format_demo_output(output)
        case output
        when ModuleResult
          output.to_h.map { |k, v| "#{k}: #{v}" }.join("\n")
        when Hash
          output.map { |k, v| "#{k}: #{v}" }.join("\n")
        else
          output.to_s
        end
      end

      def extract_modules(program)
        # This would need to be implemented based on program structure
        # For now, return modules from instance variables
        modules = {}

        program.instance_variables.each do |var|
          value = program.instance_variable_get(var)
          modules[var.to_s.delete('@').to_sym] = value if value.is_a?(Module)
        end

        modules
      end

      def create_module_examples(_module_instance, trainset)
        # Transform trainset to match module's signature
        trainset.map do |example|
          # This is simplified - would need proper field mapping
          example
        end
      end

      def replace_module(program, module_name, new_module)
        # Replace the module in the program
        var_name = "@#{module_name}"
        return unless program.instance_variable_defined?(var_name)

        program.instance_variable_set(var_name, new_module)
      end
    end
  end
end

# Register in the main module namespace for convenience
module Desiru
  BootstrapFewShot = Optimizers::BootstrapFewShot
end
