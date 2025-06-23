# frozen_string_literal: true

require 'json'

module Desiru
  module Optimizers
    # MIPROv2 - Multi-objective Instruction Prompt Optimization v2
    # Uses Bayesian optimization to optimize prompts and demonstrations across multiple objectives
    class MIPROv2 < Base
      attr_reader :optimization_history, :pareto_frontier, :trace_collector

      def initialize(metric: :exact_match, objectives: nil, **config)
        super(metric: metric, **config)
        @objectives = normalize_objectives(objectives || [metric])
        @optimization_history = []
        @pareto_frontier = []
        @gaussian_process = GaussianProcess.new
        @acquisition_function = config[:acquisition_function] || :expected_improvement
        @trace_collector = config[:trace_collector] || Core.trace_collector
        @instruction_candidates = []
        @demonstration_candidates = []
      end

      def compile(program, trainset:, valset: nil)
        trace_optimization('Starting MIPROv2 optimization', {
                             trainset_size: trainset.size,
                             valset_size: valset&.size || 0,
                             objectives: @objectives.map(&:to_s),
                             config: config
                           })

        begin
          # Initialize optimization state
          @current_program = deep_copy_program(program)
          @trainset = trainset
          @valset = valset || trainset
          @iteration = 0

          # Clear trace collector for fresh optimization
          @trace_collector.clear if config[:clear_traces]

          # Enable tracing on all modules
          enable_program_tracing(@current_program)

          # Run Bayesian optimization loop
          while @iteration < config[:max_iterations] && !should_stop?
            @iteration += 1
            trace_optimization("Iteration #{@iteration}", { phase: 'start' })

            # Generate candidates using acquisition function
            candidates = generate_candidates

            # Evaluate candidates
            evaluated_candidates = evaluate_candidates(candidates)

            # Update Gaussian Process with results
            update_gaussian_process(evaluated_candidates)

            # Update Pareto frontier for multi-objective optimization
            update_pareto_frontier(evaluated_candidates)

            # Select best candidate
            best_candidate = select_best_candidate(evaluated_candidates)

            # Apply best candidate to program
            apply_candidate(@current_program, best_candidate) if best_candidate

            # Log iteration results - always log even if no best candidate
            if best_candidate
              log_iteration_results(best_candidate, evaluated_candidates)
            elsif evaluated_candidates.any?
              # Log with the first candidate if no best found
              log_iteration_results(evaluated_candidates.first, evaluated_candidates)
            end
          end

          # Restore trace state
          disable_program_tracing(@current_program) if config[:restore_trace_state]

          # Return optimized program
          @current_program
        rescue StandardError => e
          trace_optimization('Optimization failed', { error: e.message, backtrace: e.backtrace.first(3) })
          begin
            disable_program_tracing(@current_program) if config[:restore_trace_state]
          rescue StandardError
            nil
          end

          # Return original program on error
          program
        ensure
          # Always disable tracing at the end if enabled
          begin
            disable_program_tracing(@current_program) if config[:restore_trace_state]
          rescue StandardError
            nil
          end
        end
      end

      def optimize_module(module_instance, examples)
        trace_optimization('Optimizing module with MIPROv2', {
                             module: module_instance.class.name,
                             examples_count: examples.size
                           })

        # Generate instruction variants
        instruction_variants = generate_instruction_variants(module_instance, examples)

        # Generate demonstration sets
        demo_sets = generate_demonstration_sets(module_instance, examples)

        # Evaluate all combinations
        best_config = nil
        best_score = -Float::INFINITY

        instruction_variants.each do |instruction|
          demo_sets.each do |demos|
            score = evaluate_module_config(module_instance, instruction, demos, examples)

            if score > best_score
              best_score = score
              best_config = { instruction: instruction, demos: demos }
            end
          end
        end

        # Create optimized module
        optimized = module_instance.with_demos(best_config[:demos])
        optimized.instruction = best_config[:instruction] if optimized.respond_to?(:instruction=)

        optimized
      end

      def generate_instruction_variants(module_instance, _examples)
        # Generate different instruction styles
        signature = module_instance.signature
        [
          generate_instruction(signature, 'concise', 0.2),
          generate_instruction(signature, 'detailed', 0.5),
          generate_instruction(signature, 'step-by-step', 0.8)
        ]
      end

      def generate_demonstration_sets(_module_instance, examples)
        return [[]] if examples.empty?

        # Generate different demo sets
        sets = []

        # Empty set
        sets << []

        # Random subset
        [1, 2, 3].each do |count|
          break if count > examples.size

          sets << examples.sample(count)
        end

        # Diverse set
        sets << select_diverse_demonstrations(examples, [examples.size, 3].min, Random.new) if examples.size > 1

        sets
      end

      def evaluate_module_config(module_instance, instruction, demos, examples)
        # Simple evaluation - could be enhanced
        test_module = module_instance.with_demos(demos)

        test_module.instruction = instruction if test_module.respond_to?(:instruction=) && instruction

        # Evaluate on subset of examples
        eval_examples = examples.sample([examples.size, 5].min)
        scores = eval_examples.map do |ex|
          # Extract inputs (exclude answer/output fields)
          inputs = {}
          ex.to_h.each do |k, v|
            inputs[k] = v unless %i[answer output].include?(k)
          end

          result = test_module.call(inputs)
          score_prediction(result, ex)
        rescue StandardError
          0.0
        end

        scores.empty? ? 0.0 : scores.sum.to_f / scores.size
      end

      private

      def normalize_objectives(objectives)
        objectives.map { |obj| normalize_metric(obj) }
      end

      def generate_candidates
        trace_optimization("Generating candidates", {
                             iteration: @iteration,
                             acquisition_function: @acquisition_function
                           })

        # Use Gaussian Process to guide candidate generation
        if @optimization_history.empty?
          # Initial random sampling
          generate_random_candidates(config[:num_candidates])
        else
          # Use acquisition function to generate candidates
          generate_guided_candidates(config[:num_candidates])
        end
      end

      def generate_random_candidates(num)
        (1..num).map do |i|
          {
            id: "random_#{@iteration}_#{i}",
            instruction_seed: rand,
            demo_seed: rand,
            temperature: 0.1 + (rand * 0.8),
            demo_count: rand(1..config[:max_bootstrapped_demos]),
            instruction_style: %w[concise detailed step-by-step].sample,
            demo_selection: %w[random diverse similar].sample
          }
        end
      end

      def generate_guided_candidates(num)
        candidates = []

        # Get best performers from history
        best_historical = @optimization_history
                          .sort_by { |h| -h[:scores].values.sum }
                          .first(5)

        # Generate variations of best performers
        best_historical.each do |hist|
          next unless hist[:candidate] # Skip if no candidate

          2.times do
            candidate = mutate_candidate(hist[:candidate])
            candidates << candidate
          end
        end

        # Fill remaining slots with acquisition function-guided candidates
        while candidates.size < num
          candidate = generate_acquisition_candidate
          candidates << candidate
        end

        candidates.first(num)
      end

      def mutate_candidate(base_candidate)
        return generate_random_candidates(1).first if base_candidate.nil?

        mutated = base_candidate.dup
        mutated[:id] = "mutated_#{@iteration}_#{rand(1000)}"

        # Mutate parameters with small variations
        mutated[:instruction_seed] = constrain((base_candidate[:instruction_seed] || rand) + gaussian_noise(0.1), 0, 1)
        mutated[:demo_seed] = constrain((base_candidate[:demo_seed] || rand) + gaussian_noise(0.1), 0, 1)
        mutated[:temperature] = constrain((base_candidate[:temperature] || 0.5) + gaussian_noise(0.05), 0.1, 0.9)
        mutated[:demo_count] = constrain(
          (base_candidate[:demo_count] || 2) + gaussian_noise(0.5).round,
          1,
          config[:max_bootstrapped_demos]
        )

        mutated
      end

      def generate_acquisition_candidate
        # Use acquisition function to find promising regions
        best_point = optimize_acquisition_function

        {
          id: "acquisition_#{@iteration}_#{rand(1000)}",
          instruction_seed: best_point[0],
          demo_seed: best_point[1],
          temperature: best_point[2],
          demo_count: best_point[3].round.clamp(1, config[:max_bootstrapped_demos]),
          instruction_style: select_instruction_style(best_point[0]),
          demo_selection: select_demo_strategy(best_point[1])
        }
      end

      def evaluate_candidates(candidates)
        trace_optimization("Evaluating #{candidates.size} candidates", {})

        candidates.map do |candidate|
          # Validate candidate has required fields
          next unless candidate.is_a?(Hash) && candidate[:id]

          # Apply candidate configuration to program
          test_program = deep_copy_program(@current_program)
          apply_candidate(test_program, candidate)

          # Evaluate on validation set
          scores = evaluate_multi_objective(test_program, @valset)

          # Collect traces for this candidate
          candidate_traces = collect_candidate_traces(candidate[:id])

          {
            candidate: candidate,
            scores: scores,
            traces: candidate_traces,
            timestamp: Time.now
          }
        rescue StandardError => e
          trace_optimization("Candidate evaluation failed", {
                               candidate_id: candidate[:id] || 'unknown',
                               error: e.message
                             })
          {
            candidate: candidate,
            scores: {},
            traces: [],
            timestamp: Time.now,
            error: e.message
          }
        end.compact
      end

      def evaluate_multi_objective(program, dataset)
        scores = {}

        @objectives.each do |objective|
          evaluator = create_evaluator(objective)
          result = evaluator.evaluate(program, dataset)
          scores[objective] = result[:average_score]
        end

        scores
      end

      def create_evaluator(objective)
        # Create a temporary evaluator for each objective
        self.class.superclass.new(metric: objective, config: config)
      end

      def update_gaussian_process(evaluated_candidates)
        # Convert candidates to feature vectors
        evaluated_candidates.each do |eval|
          features = candidate_to_features(eval[:candidate])
          # For multi-objective, use scalarized score
          score = scalarize_objectives(eval[:scores])
          @gaussian_process.add_observation(features, score)
        end

        @gaussian_process.update
      end

      def candidate_to_features(candidate)
        [
          candidate[:instruction_seed],
          candidate[:demo_seed],
          candidate[:temperature],
          candidate[:demo_count].to_f / config[:max_bootstrapped_demos]
        ]
      end

      def scalarize_objectives(scores)
        # Simple weighted sum - could be improved with user preferences
        weights = @objectives.map { 1.0 / @objectives.size }
        scores.values.zip(weights).map { |s, w| (s || 0) * w }.sum
      end

      def update_pareto_frontier(evaluated_candidates)
        # Add new candidates to frontier
        evaluated_candidates.each do |eval|
          @pareto_frontier << eval
        end

        # Remove dominated solutions
        @pareto_frontier = compute_pareto_frontier(@pareto_frontier)

        trace_optimization("Updated Pareto frontier", {
                             size: @pareto_frontier.size,
                             best_scores: @pareto_frontier.first(3).map { |e| e[:scores] }
                           })
      end

      def compute_pareto_frontier(candidates)
        frontier = []

        candidates.each do |candidate|
          dominated = false

          candidates.each do |other|
            next if candidate == other

            if dominates?(other[:scores], candidate[:scores])
              dominated = true
              break
            end
          end

          frontier << candidate unless dominated
        end

        frontier
      end

      def dominates?(scores1, scores2)
        # For minimization objectives, flip the comparison
        at_least_one_better = false

        @objectives.each do |obj|
          # Handle nil scores
          score1 = scores1[obj] || 0
          score2 = scores2[obj] || 0

          return false if score1 < score2

          at_least_one_better = true if score1 > score2
        end

        at_least_one_better
      end

      def select_best_candidate(evaluated_candidates)
        return nil if evaluated_candidates.empty?

        # Filter out candidates with nil scores
        valid_candidates = evaluated_candidates.reject { |c| c[:scores].nil? || c[:scores].empty? }
        return nil if valid_candidates.empty?

        # For single objective, pick best
        if @objectives.size == 1
          valid_candidates.max_by { |e| e[:scores][@objectives.first] || 0 }
        else
          # For multi-objective, pick from Pareto frontier based on preferences
          # Filter valid candidates from frontier
          valid_frontier = @pareto_frontier.reject { |c| c[:scores].nil? || c[:scores].empty? }
          return nil if valid_frontier.empty?

          valid_frontier.max_by { |e| scalarize_objectives(e[:scores]) }
        end
      end

      def apply_candidate(program, candidate)
        return unless candidate

        # Apply instruction modifications
        apply_instruction_changes(program, candidate)

        # Apply demonstration selection
        apply_demonstration_changes(program, candidate)

        # Store candidate configuration in program metadata
        return unless program.respond_to?(:metadata=)

        program.metadata[:mipro_config] = candidate
      end

      def apply_instruction_changes(program, candidate)
        modules = extract_program_modules(program)

        modules.each_value do |mod|
          next unless mod.respond_to?(:signature)

          # Generate instruction based on candidate parameters
          instruction = generate_instruction(
            mod.signature,
            candidate[:instruction_style],
            candidate[:instruction_seed]
          )

          # Apply if module supports custom instructions
          mod.instruction = instruction if mod.respond_to?(:instruction=)
        end
      end

      def apply_demonstration_changes(program, candidate)
        modules = extract_program_modules(program)

        modules.each_value do |mod|
          # Select demonstrations based on candidate strategy
          demos = select_demonstrations(
            mod,
            @trainset,
            candidate[:demo_count],
            candidate[:demo_selection],
            candidate[:demo_seed]
          )

          # Apply demonstrations
          optimized_module = mod.with_demos(demos)
          update_program_module(program, mod, optimized_module)
        end
      end

      def generate_instruction(signature, style, seed)
        # Use seed for reproducibility
        seed ||= rand # Fallback if seed is nil
        Random.new((seed * 1_000_000).to_i)

        # Handle both string and Signature object
        if signature.is_a?(String)
          # Parse signature string to extract input/output fields
          parts = signature.split('->').map(&:strip)
          return signature unless parts.size == 2

          input_fields = parts[0].split(',').map(&:strip).map { |f| f.split(':').first.strip }
          output_fields = parts[1].split(',').map(&:strip).map { |f| f.split(':').first.strip }

        # Fallback for simple signatures

        else
          # It's a Signature object
          input_fields = signature.input_fields.keys
          output_fields = signature.output_fields.keys
        end

        base_instruction = signature.to_s
        style ||= 'concise' # Default style if nil

        case style
        when 'concise'
          "Given #{input_fields.join(', ')}, output #{output_fields.join(', ')}."
        when 'detailed'
          if signature.is_a?(String)
            "Process the following inputs: #{input_fields.join(', ')}. " \
              "Generate these outputs: #{output_fields.join(', ')}. Be thorough and accurate."
          else
            input_desc = signature.input_fields.map { |k, f| "#{k} (#{f.type})" }.join(', ')
            output_desc = signature.output_fields.map { |k, f| "#{k} (#{f.type})" }.join(', ')
            "Process the following inputs: #{input_desc}. " \
              "Generate these outputs: #{output_desc}. Be thorough and accurate."
          end
        when 'step-by-step'
          "Follow these steps:\n" \
          "1. Analyze the inputs: #{input_fields.join(', ')}\n" \
          "2. Process the information carefully\n" \
          "3. Generate outputs: #{output_fields.join(', ')}"
        else
          base_instruction
        end
      end

      def select_demonstrations(module_instance, examples, count, strategy, seed)
        count ||= 0 # Default count if nil
        return [] if count.zero? || examples.empty?

        # Use seed for reproducibility
        seed ||= rand # Fallback if seed is nil
        rng = Random.new((seed * 1_000_000).to_i)
        available = examples.dup

        case strategy
        when 'random'
          available.sample(count, random: rng)
        when 'diverse'
          select_diverse_demonstrations(available, count, rng)
        when 'similar'
          select_similar_demonstrations(module_instance, available, count, rng)
        else
          available.first(count)
        end
      end

      def select_diverse_demonstrations(examples, count, rng)
        selected = []
        remaining = examples.shuffle(random: rng)

        while selected.size < count && remaining.any?
          # Add most different from current selection
          best_candidate = remaining.max_by do |ex|
            min_distance_to_selected(ex, selected)
          end

          selected << best_candidate
          remaining.delete(best_candidate)
        end

        selected
      end

      def select_similar_demonstrations(_module_instance, examples, count, rng)
        # Group by similarity and select representatives
        clusters = cluster_examples(examples, count)
        clusters.map { |cluster| cluster.sample(random: rng) }.compact.first(count)
      end

      def min_distance_to_selected(example, selected)
        return Float::INFINITY if selected.empty?

        selected.map { |sel| example_distance(example, sel) }.min
      end

      def example_distance(ex1, ex2)
        # Simple distance based on shared keys and values
        keys1 = ex1.keys.to_set
        keys2 = ex2.keys.to_set

        shared_keys = keys1 & keys2
        return 1.0 if shared_keys.empty?

        differences = shared_keys.count { |k| ex1[k] != ex2[k] }
        differences.to_f / shared_keys.size
      end

      def cluster_examples(examples, num_clusters)
        # Simple clustering - could be improved with k-means
        return [examples] if num_clusters == 1

        clusters = Array.new(num_clusters) { [] }
        examples.each_with_index do |ex, i|
          clusters[i % num_clusters] << ex
        end

        clusters.reject(&:empty?)
      end

      def collect_candidate_traces(candidate_id)
        # Filter traces that occurred during this candidate's evaluation
        @trace_collector.traces.select do |trace|
          trace.metadata[:candidate_id] == candidate_id
        end
      end

      def log_iteration_results(best_candidate, all_candidates)
        @optimization_history << {
          iteration: @iteration,
          best_candidate: best_candidate[:candidate],
          scores: best_candidate[:scores] || {},
          all_scores: all_candidates.map { |c| c[:scores] || {} },
          pareto_size: @pareto_frontier.size,
          timestamp: Time.now
        }

        trace_optimization("Iteration #{@iteration} complete", {
                             best_scores: best_candidate[:scores] || {},
                             candidates_evaluated: all_candidates.size,
                             traces_collected: @trace_collector.size
                           })
      end

      def should_stop?
        return true if @iteration >= config[:max_iterations]

        # Check if we've reached target performance
        if @optimization_history.any?
          best_score = @optimization_history.last[:scores].values.max
          return true if best_score >= config[:stop_at_score]
        end

        # Check for convergence
        if @optimization_history.size >= 5
          recent_scores = @optimization_history.last(5).map { |h| h[:scores].values.max }
          variance = statistical_variance(recent_scores)
          return true if variance < config[:convergence_threshold]
        end

        false
      end

      def statistical_variance(values)
        mean = values.sum.to_f / values.size
        values.map { |v| (v - mean)**2 }.sum / values.size
      end

      def deep_copy_program(program)
        # This needs proper implementation based on program structure
        # For now, just return the program as optimizers typically create new modules
        program
      end

      def extract_program_modules(program)
        modules = {}

        # Check instance variables
        program.instance_variables.each do |var|
          value = program.instance_variable_get(var)
          modules[var.to_s.delete('@').to_sym] = value if value.is_a?(Desiru::Module)
        end

        # Check if program has a modules method
        if program.respond_to?(:modules)
          program.modules.each do |name, mod|
            modules[name] = mod if mod.is_a?(Desiru::Module)
          end
        end

        modules
      end

      def update_program_module(program, old_module, new_module)
        # Update instance variable if it matches
        program.instance_variables.each do |var|
          value = program.instance_variable_get(var)
          program.instance_variable_set(var, new_module) if value == old_module
        end

        # Update in modules hash if program supports it
        return unless program.respond_to?(:modules) && program.modules.is_a?(Hash)

        program.modules.each do |name, mod|
          program.modules[name] = new_module if mod == old_module
        end
      end

      def enable_program_tracing(program)
        modules = extract_program_modules(program)
        modules.each_value do |mod|
          mod.enable_trace! if mod.respond_to?(:enable_trace!)
        end
      end

      def disable_program_tracing(program)
        modules = extract_program_modules(program)
        modules.each_value do |mod|
          mod.disable_trace! if mod.respond_to?(:disable_trace!)
        end
      end

      def optimize_acquisition_function
        # Simple grid search - could be improved with gradient-based optimization
        best_point = nil
        best_value = -Float::INFINITY

        10.times do
          point = [rand, rand, 0.1 + (rand * 0.8), rand * config[:max_bootstrapped_demos]]
          value = compute_acquisition_value(point)

          if value > best_value
            best_value = value
            best_point = point
          end
        end

        best_point
      end

      def compute_acquisition_value(point)
        case @acquisition_function
        when :expected_improvement
          expected_improvement(point)
        when :upper_confidence_bound
          upper_confidence_bound(point)
        else
          @gaussian_process.predict(point)[:mean]
        end
      end

      def expected_improvement(point)
        prediction = @gaussian_process.predict(point)
        mean = prediction[:mean]
        std = prediction[:std]

        return 0.0 if std.zero?

        best_so_far = @optimization_history.map { |h| scalarize_objectives(h[:scores]) }.max || 0
        z = (mean - best_so_far) / std

        # EI = (mean - best) * CDF(z) + std * PDF(z)
        ((mean - best_so_far) * standard_normal_cdf(z)) + (std * standard_normal_pdf(z))
      rescue StandardError => e
        trace_optimization("Expected improvement calculation failed", { error: e.message })
        0.0 # Return 0 on error
      end

      def upper_confidence_bound(point, beta = 2.0)
        prediction = @gaussian_process.predict(point)
        prediction[:mean] + (beta * prediction[:std])
      end

      def standard_normal_pdf(value)
        Math.exp(-0.5 * (value**2)) / Math.sqrt(2 * Math::PI)
      end

      def standard_normal_cdf(value)
        0.5 * (1 + Math.erf(value / Math.sqrt(2)))
      end

      def gaussian_noise(std_dev)
        # Box-Muller transform for Gaussian noise
        u1 = rand
        u2 = rand
        Math.sqrt(-2 * Math.log(u1)) * Math.cos(2 * Math::PI * u2) * std_dev
      end

      def constrain(value, min, max)
        value.clamp(min, max)
      end

      def select_instruction_style(seed)
        styles = %w[concise detailed step-by-step]
        styles[(seed * styles.size).to_i]
      end

      def select_demo_strategy(seed)
        strategies = %w[random diverse similar]
        strategies[(seed * strategies.size).to_i]
      end

      def default_config
        super.merge({
                      max_iterations: 20,
                      num_candidates: 8,
                      convergence_threshold: 0.001,
                      clear_traces: true,
                      restore_trace_state: true,
                      acquisition_function: :expected_improvement,
                      max_bootstrapped_demos: 3
                    })
      end

      # Simplified Gaussian Process implementation without matrix library
      class GaussianProcess
        def initialize(kernel = :rbf, length_scale = 1.0, noise = 0.1)
          @kernel = kernel
          @length_scale = length_scale
          @noise = noise
          @observations = []
          @trained = false
        end

        def add_observation(features, value)
          @observations << { features: features, value: value }
          @trained = false
        end

        def update
          # Simplified update - just mark as trained
          @trained = !@observations.empty?
        rescue StandardError => e
          Desiru.logger&.warn("Gaussian Process update failed: #{e.message}")
          @trained = false
        end

        def predict(features)
          return { mean: 0.0, std: 1.0 } unless @trained && !@observations.empty?

          # Simplified prediction using weighted average based on kernel similarity
          weights = @observations.map do |obs|
            kernel_function(features, obs[:features])
          end

          total_weight = weights.sum
          return { mean: 0.0, std: 1.0 } if total_weight.zero?

          # Normalize weights
          weights = weights.map { |w| w / total_weight }

          # Compute weighted mean
          mean = @observations.zip(weights).map { |obs, w| obs[:value] * w }.sum

          # Compute weighted variance for uncertainty
          variance = @observations.zip(weights).map do |obs, w|
            w * ((obs[:value] - mean)**2)
          end.sum

          std = Math.sqrt([variance + @noise, 0].max)

          { mean: mean, std: std }
        rescue StandardError => e
          Desiru.logger&.warn("Gaussian Process prediction failed: #{e.message}")
          { mean: 0.0, std: 1.0 }
        end

        private

        def kernel_function(features1, features2)
          # Only RBF kernel supported for now
          rbf_kernel(features1, features2)
        end

        def rbf_kernel(features1, features2)
          # Radial Basis Function kernel
          distance = euclidean_distance(features1, features2)
          Math.exp(-0.5 * ((distance / @length_scale)**2))
        end

        def euclidean_distance(features1, features2)
          Math.sqrt(features1.zip(features2).map { |a, b| (a - b)**2 }.sum)
        end
      end
    end
  end
end

# Register in the main module namespace for convenience
module Desiru
  MIPROv2 = Optimizers::MIPROv2
end
