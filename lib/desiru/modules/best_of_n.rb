# frozen_string_literal: true

module Desiru
  module Modules
    # BestOfN module that samples N outputs from a predictor and selects the best one
    # based on configurable criteria (confidence, consistency, or external validation)
    class BestOfN < Desiru::Module
      SELECTION_CRITERIA = %i[confidence consistency llm_judge custom].freeze

      DEFAULT_SIGNATURE = 'question: string -> answer: string'

      def initialize(signature = nil, model: nil, **kwargs)
        # Extract our specific options before passing to parent
        @n_samples = kwargs.delete(:n_samples) || 5
        @selection_criterion = validate_criterion(kwargs.delete(:selection_criterion) || :consistency)
        @temperature = kwargs.delete(:temperature) || 0.7
        @custom_selector = kwargs.delete(:custom_selector) # Proc that takes array of results
        @base_module = kwargs.delete(:base_module) || Modules::Predict
        @include_metadata = kwargs.delete(:include_metadata) || false

        # Use default signature if none provided
        signature ||= DEFAULT_SIGNATURE

        # Pass remaining kwargs to parent (config, demos, metadata)
        super
      end

      def forward(**inputs)
        # Generate N samples
        samples = generate_samples(inputs)

        # Select the best sample based on criterion
        best_sample = select_best(samples, inputs)

        # Include metadata if requested
        if @include_metadata || signature.output_fields.key?(:selection_metadata)
          best_sample[:selection_metadata] = build_metadata(samples, best_sample)
        end

        # Clean up internal fields
        best_sample.delete(:_confidence_score)

        best_sample
      rescue ArgumentError => e
        # Re-raise ArgumentError for missing custom selector
        raise e
      rescue StandardError => e
        Desiru.logger.error("BestOfN error: #{e.message}")
        # Fallback to single sample
        fallback_sample(inputs)
      end

      private

      def validate_criterion(criterion)
        unless SELECTION_CRITERIA.include?(criterion)
          raise ArgumentError, "Invalid selection criterion: #{criterion}. " \
                               "Must be one of: #{SELECTION_CRITERIA.join(', ')}"
        end
        criterion
      end

      def generate_samples(inputs)
        samples = []

        # Create module instance for generation
        generator = if @base_module.is_a?(Class)
                      @base_module.new(signature, model: model)
                    else
                      @base_module
                    end

        @n_samples.times do |i|
          # Add variation seed to inputs for diversity
          sample_inputs = inputs.merge(_sample_index: i)

          # Use higher temperature for diversity
          original_temp = model.instance_variable_get(:@temperature) if model.respond_to?(:instance_variable_get)

          begin
            # Temporarily set temperature if possible
            model.temperature = @temperature if model.respond_to?(:temperature=)

            # Generate sample
            sample = if generator.respond_to?(:forward)
                       generator.forward(**sample_inputs)
                     else
                       generator.call(**sample_inputs)
                     end

            # Remove the sample index from results
            sample.delete(:_sample_index)
            samples << sample
          ensure
            # Restore original temperature
            model.temperature = original_temp if model.respond_to?(:temperature=) && original_temp
          end
        end

        samples
      end

      def select_best(samples, inputs)
        case @selection_criterion
        when :confidence
          select_by_confidence(samples)
        when :consistency
          select_by_consistency(samples)
        when :llm_judge
          select_by_llm_judge(samples, inputs)
        when :custom
          select_by_custom(samples)
        else
          samples.first # Fallback
        end
      end

      def select_by_confidence(samples)
        # Ask model to rate confidence for each sample
        samples_with_scores = samples.map do |sample|
          confidence = calculate_confidence(sample)
          sample.merge(_confidence_score: confidence)
        end

        # Return sample with highest confidence (keep score for metadata)
        samples_with_scores.max_by { |s| s[:_confidence_score] }
      end

      def calculate_confidence(sample)
        # Build confidence prompt
        prompt = "Rate the confidence (0-100) for this response:\n\n"

        sample.each do |key, value|
          next if key.to_s.start_with?('_')

          prompt += "#{key}: #{value}\n"
        end

        prompt += "\nProvide only a number between 0 and 100:"

        response = model.complete(
          messages: [{ role: 'user', content: prompt }],
          temperature: 0.1
        )

        # Extract confidence score
        score = response[:content].scan(/\d+/).first&.to_i || 50
        score.clamp(0, 100)
      end

      def select_by_consistency(samples)
        # Group samples by their main output values
        output_groups = Hash.new { |h, k| h[k] = [] }

        # Find the main output field (first non-metadata field)
        main_field = signature.output_fields.keys.find do |k|
          !k.to_s.start_with?('_') && k.to_s != 'selection_metadata'
        end

        return samples.first unless main_field

        # Convert to symbol to match sample keys
        field_sym = main_field.to_sym

        # Group samples by their main output
        samples.each do |sample|
          if sample[field_sym]
            key = normalize_output(sample[field_sym])
            output_groups[key] << sample
          end
        end

        # Select the most consistent group
        largest_group = output_groups.values.max_by(&:length)

        # From the largest group, select the "centroid" - the one most similar to others
        select_centroid(largest_group)
      end

      def normalize_output(value)
        case value
        when String
          value.downcase.strip.gsub(/[[:punct:]]/, '')
        when Numeric
          value.round(2)
        when Array
          value.map { |v| normalize_output(v) }.sort
        when Hash
          value.transform_values { |v| normalize_output(v) }
        else
          value.to_s
        end
      end

      def select_centroid(group)
        return group.first if group.length == 1

        # For now, return the middle element (could be improved with similarity metrics)
        group[group.length / 2]
      end

      def select_by_llm_judge(samples, inputs)
        # Build judge prompt
        judge_prompt = "Given the following input and multiple response options, " \
                       "select the best response:\n\n"

        # Add original inputs
        judge_prompt += "Input:\n"
        inputs.each do |key, value|
          judge_prompt += "  #{key}: #{value}\n"
        end

        # Add all samples
        judge_prompt += "\nResponse Options:\n"
        samples.each_with_index do |sample, i|
          judge_prompt += "\n--- Option #{i + 1} ---\n"
          sample.each do |key, value|
            next if key.to_s.start_with?('_')

            judge_prompt += "#{key}: #{value}\n"
          end
        end

        judge_prompt += "\nSelect the best option (1-#{samples.length}) and briefly explain why:"

        response = model.complete(
          messages: [{ role: 'user', content: judge_prompt }],
          temperature: 0.1
        )

        # Extract selected index
        selection_match = response[:content].match(/option\s*#?(\d+)/i)
        selected_index = if selection_match
                           selection_match[1].to_i - 1
                         else
                           0
                         end

        selected_index = selected_index.clamp(0, samples.length - 1)
        samples[selected_index]
      end

      def select_by_custom(samples)
        unless @custom_selector.respond_to?(:call)
          raise ArgumentError, "Custom selector must be provided when using :custom criterion"
        end

        @custom_selector.call(samples) || samples.first
      end

      def build_metadata(samples, selected)
        metadata = {
          total_samples: samples.length,
          selection_criterion: @selection_criterion,
          temperature: @temperature
        }

        # Add criterion-specific metadata
        case @selection_criterion
        when :consistency
          # Count how many samples agree with the selected one
          main_field = signature.output_fields.keys.find do |k|
            !k.to_s.start_with?('_') && k.to_s != 'selection_metadata'
          end

          if main_field
            # Convert to symbol to match sample keys
            field_sym = main_field.to_sym
            if selected[field_sym]
              selected_value = normalize_output(selected[field_sym])
              agreement_count = samples.count do |s|
                normalize_output(s[field_sym]) == selected_value
              end
              metadata[:agreement_rate] = agreement_count.to_f / samples.length
            end
          end
        when :confidence
          # Include confidence scores if available
          metadata[:selected_confidence] = selected[:_confidence_score] if selected[:_confidence_score]
        end

        metadata
      end

      def fallback_sample(inputs)
        # Generate a single sample as fallback
        generator = if @base_module.is_a?(Class)
                      @base_module.new(signature, model: model)
                    else
                      @base_module
                    end

        if generator.respond_to?(:forward)
          generator.forward(**inputs)
        else
          generator.call(**inputs)
        end
      end
    end
  end
end

# Register in the main module namespace for convenience
module Desiru
  BestOfN = Modules::BestOfN
end
