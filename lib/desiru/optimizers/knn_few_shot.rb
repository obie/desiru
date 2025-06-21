# frozen_string_literal: true

module Desiru
  module Optimizers
    # KNNFewShot optimizer that uses k-Nearest Neighbors to find similar examples
    # for few-shot learning. It finds the most similar training examples to each
    # input and uses them as demonstrations.
    class KNNFewShot < Base
      def initialize(config = {})
        super
        @k = config[:k] || 3 # Number of nearest neighbors
        @similarity_metric = config[:similarity_metric] || :cosine
        @embedding_cache = {}
      end

      def compile(program, trainset, **_kwargs)
        # Build index of training examples
        build_example_index(trainset)

        # Create optimized program with KNN-based few-shot selection
        optimized_program = program.dup

        # Wrap each predict module with KNN few-shot enhancement
        optimized_program.predictors.each do |name, predictor|
          optimized_predictor = create_knn_predictor(predictor, name)
          optimized_program.instance_variable_set("@#{name}", optimized_predictor)
        end

        optimized_program
      end

      private

      def build_example_index(trainset)
        @example_embeddings = []
        @example_data = []

        trainset.each do |example|
          # Create text representation of the example
          example_text = serialize_example(example)

          # Generate embedding (simplified - in practice, use a real embedding model)
          embedding = generate_embedding(example_text)

          @example_embeddings << embedding
          @example_data << example
        end
      end

      def create_knn_predictor(original_predictor, predictor_name)
        knn_predictor = original_predictor.dup
        example_embeddings = @example_embeddings
        example_data = @example_data
        k = @k
        similarity_metric = @similarity_metric

        # Override the forward method to include KNN examples
        knn_predictor.define_singleton_method(:forward) do |**inputs|
          # Find nearest neighbors for this input
          input_text = inputs.map { |k, v| "#{k}: #{v}" }.join("\n")
          input_embedding = generate_embedding(input_text)

          nearest_examples = find_nearest_neighbors(
            input_embedding,
            example_embeddings,
            example_data,
            k,
            similarity_metric
          )

          # Format examples for few-shot learning
          demonstrations = format_demonstrations(nearest_examples, predictor_name)

          # Enhance the prompt with demonstrations
          enhanced_prompt = build_enhanced_prompt(inputs, demonstrations)

          # Call original predictor with enhanced prompt
          super(**inputs, few_shot_examples: enhanced_prompt)
        end

        knn_predictor
      end

      def generate_embedding(text)
        # Cache embeddings to avoid recomputation
        return @embedding_cache[text] if @embedding_cache.key?(text)

        # Simplified embedding generation
        # In practice, use a real embedding model like OpenAI's text-embedding-ada-002
        words = text.downcase.split(/\W+/)
        embedding = Array.new(100, 0.0)

        words.each do |word|
          # Simple hash-based pseudo-embedding
          hash_value = word.hash
          100.times do |i|
            embedding[i] += Math.sin(hash_value * (i + 1)) / Math.sqrt(words.length + 1)
          end
        end

        # Normalize
        magnitude = Math.sqrt(embedding.sum { |x| x * x })
        embedding = embedding.map { |x| x / (magnitude + 1e-10) }

        @embedding_cache[text] = embedding
        embedding
      end

      def find_nearest_neighbors(query_embedding, embeddings, data, num_neighbors, metric)
        # Calculate distances
        distances = embeddings.map.with_index do |embedding, idx|
          distance = case metric
                     when :cosine
                       cosine_distance(query_embedding, embedding)
                     when :euclidean
                       euclidean_distance(query_embedding, embedding)
                     else
                       raise ArgumentError, "Unknown similarity metric: #{metric}"
                     end
          { distance: distance, index: idx }
        end

        # Sort by distance and take top k
        nearest = distances.sort_by { |d| d[:distance] }.take(num_neighbors)
        nearest.map { |d| data[d[:index]] }
      end

      def cosine_distance(vec1, vec2)
        dot_product = vec1.zip(vec2).sum { |a, b| a * b }
        1.0 - dot_product # Convert similarity to distance
      end

      def euclidean_distance(vec1, vec2)
        Math.sqrt(vec1.zip(vec2).sum { |a, b| (a - b)**2 })
      end

      def serialize_example(example)
        parts = []

        # Add inputs
        if example[:inputs]
          parts << "Inputs:"
          example[:inputs].each { |k, v| parts << "  #{k}: #{v}" }
        end

        # Add expected outputs
        if example[:outputs]
          parts << "Outputs:"
          example[:outputs].each { |k, v| parts << "  #{k}: #{v}" }
        end

        parts.join("\n")
      end

      def format_demonstrations(examples, _predictor_name)
        demonstrations = []

        examples.each_with_index do |example, idx|
          demo = "Example #{idx + 1}:\n"

          if example[:inputs]
            demo += "Input:\n"
            example[:inputs].each { |k, v| demo += "  #{k}: #{v}\n" }
          end

          if example[:outputs]
            demo += "Output:\n"
            example[:outputs].each { |k, v| demo += "  #{k}: #{v}\n" }
          end

          demonstrations << demo
        end

        demonstrations.join("\n---\n")
      end

      def build_enhanced_prompt(_inputs, demonstrations)
        prompt = "Here are some similar examples:\n\n"
        prompt += demonstrations
        prompt += "\n\nNow, given the following input, provide the output:\n"
        prompt
      end
    end
  end
end
