# frozen_string_literal: true

module Desiru
  module Modules
    # Retrieve module for RAG (Retrieval Augmented Generation)
    # Implements vector search capabilities with pluggable backends
    class Retrieve < Module
      attr_reader :backend

      def initialize(signature = nil, backend: nil, **)
        # Default signature for retrieval operations
        signature ||= 'query: string, k: integer? -> documents: list, scores: list'

        super(signature, **)

        # Initialize backend
        @backend = backend || InMemoryBackend.new
        validate_backend!
      end

      def forward(**inputs)
        query = inputs[:query]
        # Handle k parameter - it might come as nil if optional
        # Note: 'k' is the standard parameter name in information retrieval
        k = inputs.fetch(:k, 5)
        k = 5 if k.nil? # Ensure we have a value even if nil was passed

        # Perform retrieval using the backend
        results = backend.search(query, k: k)

        # Separate documents and scores
        documents = results.map { |r| r[:document] }
        scores = results.map { |r| r[:score] }

        { documents: documents, scores: scores }
      end

      # Add documents to the retrieval index
      def add_documents(documents, embeddings: nil)
        backend.add(documents, embeddings: embeddings)
      end

      # Clear the retrieval index
      def clear_index
        backend.clear
      end

      # Get the current document count
      def document_count
        backend.size
      end

      private

      def validate_backend!
        required_methods = %i[add search clear size]
        missing_methods = required_methods.reject { |m| backend.respond_to?(m) }

        return unless missing_methods.any?

        raise ConfigurationError, "Backend must implement: #{missing_methods.join(', ')}"
      end
    end

    # Abstract base class for retrieval backends
    class Backend
      def add(_documents, embeddings: nil)
        raise NotImplementedError, 'Subclasses must implement #add'
      end

      def search(_query, k: 5) # rubocop:disable Naming/MethodParameterName
        raise NotImplementedError, 'Subclasses must implement #search'
      end

      def clear
        raise NotImplementedError, 'Subclasses must implement #clear'
      end

      def size
        raise NotImplementedError, 'Subclasses must implement #size'
      end
    end

    # In-memory backend implementation for development and testing
    class InMemoryBackend < Backend
      def initialize(distance_metric: :cosine)
        super()
        @documents = []
        @embeddings = []
        @distance_metric = distance_metric
      end

      def add(documents, embeddings: nil)
        documents = Array(documents)

        # If embeddings provided, they must match document count
        if embeddings
          embeddings = Array(embeddings)
          if embeddings.size != documents.size
            raise ArgumentError, "Embeddings count (#{embeddings.size}) must match documents count (#{documents.size})"
          end
        else
          # Generate simple embeddings based on document content (for demo purposes)
          embeddings = documents.map { |doc| generate_simple_embedding(doc) }
        end

        # Store documents and embeddings
        @documents.concat(documents)
        @embeddings.concat(embeddings)
      end

      def search(query, k: 5) # rubocop:disable Naming/MethodParameterName
        return [] if @documents.empty?

        # Generate query embedding
        query_embedding = generate_simple_embedding(query)

        # Calculate distances to all documents
        distances = @embeddings.map.with_index do |embedding, idx|
          distance = calculate_distance(query_embedding, embedding)
          { document: @documents[idx], score: distance, index: idx }
        end

        # Sort by distance (ascending for distance, would be descending for similarity)
        sorted = case @distance_metric
                 when :cosine
                   # For cosine similarity, higher is better, so sort descending
                   distances.sort_by { |d| -d[:score] }
                 else
                   # For distance metrics, lower is better
                   distances.sort_by { |d| d[:score] }
                 end

        # Return top k results
        sorted.first(k)
      end

      def clear
        @documents.clear
        @embeddings.clear
      end

      def size
        @documents.size
      end

      private

      def generate_simple_embedding(text)
        # Simple embedding: character frequency vector
        # In production, use proper embedding models
        text = text.to_s.downcase

        # Create a 26-dimensional vector for a-z frequency
        embedding = Array.new(26, 0.0)

        text.each_char do |char|
          if char.between?('a', 'z')
            idx = char.ord - 'a'.ord
            embedding[idx] += 1.0
          end
        end

        # Normalize the vector
        magnitude = Math.sqrt(embedding.sum { |x| x**2 })
        embedding.map! { |x| x / magnitude } if magnitude.positive?

        embedding
      end

      def calculate_distance(vec1, vec2)
        case @distance_metric
        when :cosine
          cosine_similarity(vec1, vec2)
        when :euclidean
          euclidean_distance(vec1, vec2)
        else
          raise ArgumentError, "Unknown distance metric: #{@distance_metric}"
        end
      end

      def cosine_similarity(vec1, vec2)
        # Cosine similarity: dot product of normalized vectors
        # Since we pre-normalize embeddings, this is just dot product
        vec1.zip(vec2).sum { |a, b| a * b }

        # Return similarity (1.0 = identical, 0.0 = orthogonal)
      end

      def euclidean_distance(vec1, vec2)
        # Euclidean distance
        Math.sqrt(vec1.zip(vec2).sum { |a, b| (a - b)**2 })
      end
    end
  end
end

# Register in the main module namespace for convenience
module Desiru
  Retrieve = Modules::Retrieve
end
