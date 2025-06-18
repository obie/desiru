# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Modules::Retrieve do
  let(:model) { double('model') }
  let(:retrieve_module) { described_class.new(model: model) }

  describe '#initialize' do
    it 'creates module with default signature' do
      expect(retrieve_module.signature.to_s).to eq('query: string, k: integer? -> documents: list, scores: list')
    end

    it 'accepts custom signature' do
      custom_signature = 'search_query: string -> results: list'
      custom_module = described_class.new(custom_signature, model: model)
      expect(custom_module.signature.to_s).to eq(custom_signature)
    end

    it 'uses InMemoryBackend by default' do
      expect(retrieve_module.backend).to be_a(Desiru::Modules::InMemoryBackend)
    end

    it 'accepts custom backend' do
      custom_backend = double('backend', add: nil, search: [], clear: nil, size: 0)
      custom_module = described_class.new(model: model, backend: custom_backend)
      expect(custom_module.backend).to eq(custom_backend)
    end

    it 'validates backend has required methods' do
      invalid_backend = double('invalid_backend')
      expect { described_class.new(model: model, backend: invalid_backend) }
        .to raise_error(Desiru::ConfigurationError, /Backend must implement/)
    end
  end

  describe '#forward' do
    before do
      retrieve_module.add_documents([
                                      'Ruby is a dynamic programming language',
                                      'Python is great for data science',
                                      'Ruby on Rails is a web framework',
                                      'JavaScript runs in the browser',
                                      'Ruby has elegant syntax'
                                    ])
    end

    it 'retrieves relevant documents' do
      result = retrieve_module.call(query: 'Ruby programming', k: 3)

      expect(result).to be_a(Desiru::ModuleResult)
      expect(result.documents).to be_an(Array)
      expect(result.scores).to be_an(Array)
      expect(result.documents.size).to eq(3)
      expect(result.scores.size).to eq(3)
    end

    it 'uses default k value when not provided' do
      result = retrieve_module.call(query: 'programming')
      expect(result.documents.size).to eq(5) # Default k is 5
    end

    it 'respects custom k value' do
      result = retrieve_module.call(query: 'programming', k: 2)
      expect(result.documents.size).to eq(2)
    end

    it 'returns empty results for empty index' do
      retrieve_module.clear_index
      result = retrieve_module.call(query: 'test')

      expect(result.documents).to eq([])
      expect(result.scores).to eq([])
    end
  end

  describe '#add_documents' do
    it 'adds single document' do
      expect(retrieve_module.document_count).to eq(0)
      retrieve_module.add_documents('Test document')
      expect(retrieve_module.document_count).to eq(1)
    end

    it 'adds multiple documents' do
      documents = ['Doc 1', 'Doc 2', 'Doc 3']
      retrieve_module.add_documents(documents)
      expect(retrieve_module.document_count).to eq(3)
    end

    it 'accepts custom embeddings' do
      documents = ['Doc 1', 'Doc 2']
      embeddings = [[0.1, 0.2, 0.3], [0.4, 0.5, 0.6]]

      expect { retrieve_module.add_documents(documents, embeddings: embeddings) }
        .not_to raise_error
    end
  end

  describe '#clear_index' do
    it 'removes all documents' do
      retrieve_module.add_documents(['Doc 1', 'Doc 2', 'Doc 3'])
      expect(retrieve_module.document_count).to eq(3)

      retrieve_module.clear_index
      expect(retrieve_module.document_count).to eq(0)
    end
  end

  describe '#document_count' do
    it 'returns current document count' do
      expect(retrieve_module.document_count).to eq(0)

      retrieve_module.add_documents('Doc 1')
      expect(retrieve_module.document_count).to eq(1)

      retrieve_module.add_documents(['Doc 2', 'Doc 3'])
      expect(retrieve_module.document_count).to eq(3)
    end
  end
end

RSpec.describe Desiru::Modules::InMemoryBackend do
  let(:backend) { described_class.new }

  describe '#initialize' do
    it 'creates backend with cosine distance by default' do
      expect(backend.instance_variable_get(:@distance_metric)).to eq(:cosine)
    end

    it 'accepts custom distance metric' do
      euclidean_backend = described_class.new(distance_metric: :euclidean)
      expect(euclidean_backend.instance_variable_get(:@distance_metric)).to eq(:euclidean)
    end
  end

  describe '#add' do
    it 'adds documents with auto-generated embeddings' do
      backend.add(['Document 1', 'Document 2'])
      expect(backend.size).to eq(2)
    end

    it 'adds documents with provided embeddings' do
      documents = ['Doc 1', 'Doc 2']
      embeddings = [Array.new(26, 0.1), Array.new(26, 0.2)]

      backend.add(documents, embeddings: embeddings)
      expect(backend.size).to eq(2)
    end

    it 'raises error when embedding count mismatches document count' do
      documents = ['Doc 1', 'Doc 2']
      embeddings = [Array.new(26, 0.1)] # Only one embedding

      expect { backend.add(documents, embeddings: embeddings) }
        .to raise_error(ArgumentError, /must match documents count/)
    end
  end

  describe '#search' do
    before do
      backend.add([
                    'Ruby programming',
                    'Python programming',
                    'Ruby on Rails',
                    'JavaScript',
                    'Ruby gems'
                  ])
    end

    it 'returns top k results' do
      results = backend.search('Ruby', k: 2)

      expect(results.size).to eq(2)
      expect(results.first).to include(:document, :score, :index)
    end

    it 'returns all results when k exceeds document count' do
      results = backend.search('programming', k: 10)
      expect(results.size).to eq(5)
    end

    it 'returns empty array for empty index' do
      backend.clear
      results = backend.search('test')
      expect(results).to eq([])
    end

    context 'with cosine similarity' do
      it 'returns higher scores for more similar documents' do
        results = backend.search('Ruby programming', k: 5)
        scores = results.map { |r| r[:score] }

        # Scores should be in descending order (higher similarity first)
        expect(scores).to eq(scores.sort.reverse)
      end
    end

    context 'with euclidean distance' do
      let(:backend) { described_class.new(distance_metric: :euclidean) }

      it 'returns lower scores for more similar documents' do
        backend.add(%w[Ruby Python JavaScript])
        results = backend.search('Ruby', k: 3)
        scores = results.map { |r| r[:score] }

        # Scores should be in ascending order (lower distance first)
        expect(scores).to eq(scores.sort)
      end
    end
  end

  describe '#clear' do
    it 'removes all documents and embeddings' do
      backend.add(['Doc 1', 'Doc 2', 'Doc 3'])
      expect(backend.size).to eq(3)

      backend.clear
      expect(backend.size).to eq(0)
    end
  end

  describe '#size' do
    it 'returns current document count' do
      expect(backend.size).to eq(0)

      backend.add('Doc 1')
      expect(backend.size).to eq(1)

      backend.add(['Doc 2', 'Doc 3'])
      expect(backend.size).to eq(3)
    end
  end

  describe 'embedding generation' do
    it 'generates normalized embeddings' do
      backend.add(['test'])

      # Access the embeddings directly for testing
      embeddings = backend.instance_variable_get(:@embeddings)
      embedding = embeddings.first

      # Check it's normalized (magnitude ~= 1)
      magnitude = Math.sqrt(embedding.sum { |x| x**2 })
      expect(magnitude).to be_within(0.001).of(1.0)
    end

    it 'handles empty strings' do
      expect { backend.add(['']) }.not_to raise_error
    end

    it 'handles non-alphabetic characters' do
      expect { backend.add(['123!@#']) }.not_to raise_error
    end
  end
end

RSpec.describe Desiru::Modules::Backend do
  let(:backend) { described_class.new }

  describe 'abstract methods' do
    it 'raises NotImplementedError for #add' do
      expect { backend.add(['doc']) }
        .to raise_error(NotImplementedError, /Subclasses must implement #add/)
    end

    it 'raises NotImplementedError for #search' do
      expect { backend.search('query') }
        .to raise_error(NotImplementedError, /Subclasses must implement #search/)
    end

    it 'raises NotImplementedError for #clear' do
      expect { backend.clear }
        .to raise_error(NotImplementedError, /Subclasses must implement #clear/)
    end

    it 'raises NotImplementedError for #size' do
      expect { backend.size }
        .to raise_error(NotImplementedError, /Subclasses must implement #size/)
    end
  end
end

# Integration test
RSpec.describe 'Retrieve module integration' do
  let(:model) { double('model') }

  it 'works end-to-end with retrieval and search' do
    retrieve = Desiru::Retrieve.new(model: model)

    # Add some documents
    documents = [
      'Desiru is a Ruby implementation of DSPy',
      'DSPy enables declarative language model programming',
      'Ruby is a beautiful programming language',
      'Machine learning with Ruby is possible',
      'Language models are transforming AI'
    ]

    retrieve.add_documents(documents)

    # Search for relevant documents
    result = retrieve.call(query: 'DSPy Ruby implementation', k: 3)

    # Verify results
    expect(result.documents).to include('Desiru is a Ruby implementation of DSPy')
    expect(result.documents.size).to eq(3)
    expect(result.scores.size).to eq(3)
    expect(result.scores.first).to be_a(Float)
  end
end
