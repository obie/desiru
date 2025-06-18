# frozen_string_literal: true

require_relative '../lib/desiru'

# Example: Using the Retrieve module for RAG (Retrieval Augmented Generation)

# Create a dummy model for demonstration
class DummyModel
  def complete(prompt, **_options)
    { content: "Answer based on retrieved context: #{prompt[:user]}" }
  end
end

# Initialize the Retrieve module
retrieve = Desiru::Retrieve.new(model: DummyModel.new)

# Add some documents to the knowledge base
documents = [
  'Desiru is a Ruby implementation of DSPy for programming language models.',
  'DSPy (Declarative Self-improving Language Programs) enables systematic optimization of LM prompts and weights.',
  'Ruby is a dynamic, open source programming language with a focus on simplicity and productivity.',
  'The Retrieve module implements vector search for RAG (Retrieval Augmented Generation) applications.',
  'RAG combines retrieval from a knowledge base with language model generation for more accurate responses.',
  'Vector embeddings enable semantic search by representing text as high-dimensional numerical vectors.',
  'The InMemoryBackend stores documents and embeddings in memory for fast prototyping.',
  'Production systems might use vector databases like Pinecone, Weaviate, or Qdrant.'
]

puts "Adding #{documents.size} documents to the retrieval index..."
retrieve.add_documents(documents)
puts "Index now contains #{retrieve.document_count} documents\n\n"

# Perform some searches
queries = [
  { query: 'What is Desiru?', k: 3 },
  { query: 'vector search implementation', k: 2 },
  { query: 'Ruby programming', k: 4 }
]

queries.each do |params|
  puts "Query: '#{params[:query]}' (top #{params[:k]} results)"
  puts '-' * 50

  result = retrieve.call(**params)

  result.documents.each_with_index do |doc, idx|
    score = result.scores[idx]
    puts "#{idx + 1}. [Score: #{score.round(3)}] #{doc}"
  end

  puts "\n"
end

# Example: Using custom embeddings
puts "Example with custom embeddings:"
puts '-' * 50

# Create simple one-hot encoded embeddings for demonstration
custom_docs = %w[apple banana cherry]
custom_embeddings = [
  [1.0, 0.0, 0.0],  # apple
  [0.0, 1.0, 0.0],  # banana
  [0.0, 0.0, 1.0]   # cherry
]

# Create a new retrieve instance with custom backend
custom_retrieve = Desiru::Retrieve.new(
  model: DummyModel.new,
  backend: Desiru::Modules::InMemoryBackend.new(distance_metric: :euclidean)
)

custom_retrieve.add_documents(custom_docs, embeddings: custom_embeddings)

# Search with a custom query embedding # Closer to apple
results = custom_retrieve.backend.search('custom', k: 3)

puts "Custom embedding search results:"
results.each_with_index do |result, idx|
  puts "#{idx + 1}. #{result[:document]} (distance: #{result[:score].round(3)})"
end
