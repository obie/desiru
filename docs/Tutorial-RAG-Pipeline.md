# Tutorial: Building a RAG Pipeline

Retrieval-Augmented Generation (RAG) is a powerful pattern for grounding LLM responses in specific knowledge. This tutorial will guide you through building a production-ready RAG system with Desiru.

## What You'll Build

We'll create a customer support bot that:
- Searches through documentation
- Retrieves relevant information
- Generates accurate, grounded responses
- Includes source citations

## Prerequisites

```ruby
# Gemfile
gem 'desiru'
gem 'pinecone' # or your preferred vector database
gem 'pdf-reader' # for document processing
```

## Step 1: Document Processing

First, let's build a document processor to prepare our knowledge base:

```ruby
require 'desiru'
require 'pdf-reader'

class DocumentProcessor
  def initialize
    @chunker = Desiru::Predict.new(
      "text: string, max_tokens: int -> chunks: list[string]",
      descriptions: {
        text: "The document text to split",
        max_tokens: "Maximum tokens per chunk (aim for ~500)",
        chunks: "Document split into semantic chunks"
      }
    )
    
    @embedder = Desiru::Models::OpenAI.new(
      model: 'text-embedding-ada-002'
    )
  end
  
  def process_pdf(file_path)
    # Extract text from PDF
    reader = PDF::Reader.new(file_path)
    text = reader.pages.map(&:text).join("\n")
    
    # Split into chunks
    chunks = @chunker.call(
      text: text,
      max_tokens: 500
    ).chunks
    
    # Generate embeddings
    chunks.map do |chunk|
      embedding = @embedder.embed(chunk)
      {
        text: chunk,
        embedding: embedding,
        source: file_path,
        metadata: extract_metadata(chunk)
      }
    end
  end
  
  private
  
  def extract_metadata(chunk)
    # Extract section headers, page numbers, etc.
    {
      section: chunk.match(/^#+ (.+)$/)&.[](1),
      has_code: chunk.include?('```'),
      length: chunk.length
    }
  end
end
```

## Step 2: Vector Store Setup

Set up your vector database for efficient retrieval:

```ruby
class VectorStore
  def initialize(index_name: 'support-docs')
    @index = Pinecone::Index.new(index_name)
    @namespace = 'customer-support'
  end
  
  def add_documents(documents)
    vectors = documents.map.with_index do |doc, i|
      {
        id: "doc_#{Time.now.to_i}_#{i}",
        values: doc[:embedding],
        metadata: {
          text: doc[:text],
          source: doc[:source],
          **doc[:metadata]
        }
      }
    end
    
    @index.upsert(vectors: vectors, namespace: @namespace)
  end
  
  def search(query_embedding, k: 5, filter: nil)
    results = @index.query(
      vector: query_embedding,
      top_k: k,
      namespace: @namespace,
      filter: filter,
      include_metadata: true
    )
    
    results['matches'].map do |match|
      {
        text: match['metadata']['text'],
        score: match['score'],
        source: match['metadata']['source'],
        metadata: match['metadata']
      }
    end
  end
end
```

## Step 3: Build the RAG Module

Now let's create our RAG module using Desiru's components:

```ruby
class RAGModule < Desiru::Program
  def initialize(vector_store)
    @vector_store = vector_store
    @embedder = Desiru::Models::OpenAI.new(
      model: 'text-embedding-ada-002'
    )
    
    # Query understanding
    @query_enhancer = Desiru::ChainOfThought.new(
      "query: string -> enhanced_query: string, search_terms: list[string]",
      descriptions: {
        query: "The user's original question",
        enhanced_query: "Expanded query with synonyms and related terms",
        search_terms: "Key terms to search for"
      }
    )
    
    # Answer generation with citations
    @generator = Desiru::ChainOfThought.new(
      "question: string, context: list[string] -> answer: string, citations: list[int]",
      descriptions: {
        question: "The user's question",
        context: "Retrieved documents (numbered)",
        answer: "Comprehensive answer based on context",
        citations: "Indices of context documents used"
      }
    )
    
    # Answer quality check
    @validator = Desiru::Predict.new(
      "question: string, answer: string, context: list[string] -> is_grounded: bool, confidence: float"
    )
  end
  
  def forward(question:, k: 5)
    # Enhance the query
    enhanced = @query_enhancer.call(query: question)
    
    # Generate embedding
    query_embedding = @embedder.embed(enhanced.enhanced_query)
    
    # Retrieve documents
    retrieved_docs = @vector_store.search(
      query_embedding,
      k: k,
      filter: build_filter(enhanced.search_terms)
    )
    
    # Prepare context
    context = retrieved_docs.map.with_index do |doc, i|
      "[#{i}] #{doc[:text]}"
    end
    
    # Generate answer
    result = @generator.call(
      question: question,
      context: context
    )
    
    # Validate grounding
    validation = @validator.call(
      question: question,
      answer: result.answer,
      context: context
    )
    
    # Return structured response
    {
      answer: result.answer,
      citations: result.citations.map { |i| retrieved_docs[i] },
      confidence: validation.confidence,
      is_grounded: validation.is_grounded,
      reasoning: result.reasoning
    }
  end
  
  private
  
  def build_filter(search_terms)
    # Build metadata filter based on search terms
    # This is vector-db specific
    nil
  end
end
```

## Step 4: Production Enhancements

### Caching Layer

Add caching to reduce API calls and improve response time:

```ruby
class CachedRAG < Desiru::Program
  def initialize(vector_store, cache_ttl: 3600)
    @rag = RAGModule.new(vector_store)
    @cache = Redis.new
    @cache_ttl = cache_ttl
  end
  
  def forward(question:, **options)
    cache_key = "rag:#{Digest::SHA256.hexdigest(question)}:#{options.hash}"
    
    # Check cache
    cached = @cache.get(cache_key)
    return JSON.parse(cached, symbolize_names: true) if cached
    
    # Generate response
    result = @rag.call(question: question, **options)
    
    # Cache if high confidence
    if result[:confidence] > 0.8
      @cache.setex(cache_key, @cache_ttl, result.to_json)
    end
    
    result
  end
end
```

### Conversation Memory

Add context awareness for multi-turn conversations:

```ruby
class ConversationalRAG < Desiru::Program
  def initialize(vector_store)
    @rag = RAGModule.new(vector_store)
    @conversation_buffer = []
    
    @context_compressor = Desiru::Predict.new(
      "conversation: list[string], new_question: string -> standalone_question: string",
      descriptions: {
        conversation: "Previous Q&A pairs",
        new_question: "The latest question",
        standalone_question: "Self-contained question with context"
      }
    )
  end
  
  def forward(question:, **options)
    # Make question standalone
    standalone_q = question
    
    if @conversation_buffer.any?
      result = @context_compressor.call(
        conversation: @conversation_buffer.last(5),
        new_question: question
      )
      standalone_q = result.standalone_question
    end
    
    # Get answer
    answer = @rag.call(question: standalone_q, **options)
    
    # Update conversation buffer
    @conversation_buffer << "Q: #{question}\nA: #{answer[:answer]}"
    
    answer
  end
  
  def reset_conversation
    @conversation_buffer = []
  end
end
```

### Hybrid Search

Combine semantic and keyword search for better retrieval:

```ruby
class HybridRetriever
  def initialize(vector_store, keyword_index)
    @vector_store = vector_store
    @keyword_index = keyword_index
    @embedder = Desiru::Models::OpenAI.new(
      model: 'text-embedding-ada-002'
    )
  end
  
  def search(query, k: 5, alpha: 0.7)
    # Semantic search
    embedding = @embedder.embed(query)
    semantic_results = @vector_store.search(embedding, k: k * 2)
    
    # Keyword search
    keyword_results = @keyword_index.search(query, k: k * 2)
    
    # Merge results with weighted scoring
    merged = {}
    
    semantic_results.each do |doc|
      merged[doc[:text]] ||= { doc: doc, score: 0 }
      merged[doc[:text]][:score] += doc[:score] * alpha
    end
    
    keyword_results.each do |doc|
      merged[doc[:text]] ||= { doc: doc, score: 0 }
      merged[doc[:text]][:score] += doc[:score] * (1 - alpha)
    end
    
    # Return top k
    merged.values
      .sort_by { |item| -item[:score] }
      .first(k)
      .map { |item| item[:doc] }
  end
end
```

## Step 5: Complete System

Here's how to put it all together:

```ruby
# Initialize components
processor = DocumentProcessor.new
vector_store = VectorStore.new
rag = ConversationalRAG.new(vector_store)

# Process documents
Dir.glob("docs/*.pdf").each do |pdf|
  documents = processor.process_pdf(pdf)
  vector_store.add_documents(documents)
end

# Create API endpoint
require 'desiru/api'

api = Desiru::API.create do
  register_module '/ask', rag, 
    description: 'Ask questions about our documentation'
end

# Add monitoring
api.use Desiru::API::Middleware::Monitoring.new(
  metrics_collector: PrometheusExporter::Client.default
)

# Run the service
run api.to_rack_app
```

## Step 6: Testing

Test your RAG pipeline thoroughly:

```ruby
RSpec.describe RAGModule do
  let(:vector_store) { instance_double(VectorStore) }
  let(:rag) { described_class.new(vector_store) }
  
  describe '#forward' do
    it 'retrieves relevant documents' do
      allow(vector_store).to receive(:search).and_return([
        { text: 'Ruby is a programming language', score: 0.9 }
      ])
      
      result = rag.call(question: "What is Ruby?")
      
      expect(result[:answer]).to include('programming language')
      expect(result[:is_grounded]).to be true
    end
    
    it 'handles questions without relevant context' do
      allow(vector_store).to receive(:search).and_return([])
      
      result = rag.call(question: "What is the weather?")
      
      expect(result[:confidence]).to be < 0.5
      expect(result[:answer]).to include("don't have information")
    end
  end
end
```

## Optimization Tips

1. **Chunk Size**: Experiment with different chunk sizes (300-800 tokens)
2. **Retrieval Count**: Balance between context and noise (3-10 documents)
3. **Reranking**: Add a reranking step for better precision
4. **Query Expansion**: Use synonyms and related terms
5. **Metadata Filtering**: Use document metadata to improve relevance

## Advanced Features

### Multi-Index Search

```ruby
class MultiIndexRAG < Desiru::Program
  def initialize(indexes)
    @indexes = indexes # { faq: vector_store1, docs: vector_store2 }
    @router = Desiru::Predict.new(
      "question -> index_name: Literal[#{indexes.keys.map(&:to_s).join(',')}]"
    )
  end
  
  def forward(question:)
    # Route to appropriate index
    index_name = @router.call(question: question).index_name.to_sym
    vector_store = @indexes[index_name]
    
    # Continue with RAG pipeline...
  end
end
```

### Source Tracking

```ruby
class SourceAwareRAG < RAGModule
  def forward(question:, **options)
    result = super
    
    # Add source information
    result[:sources] = result[:citations].map do |doc|
      {
        file: doc[:source],
        section: doc[:metadata][:section],
        relevance: doc[:score]
      }
    end.uniq
    
    result
  end
end
```

## Monitoring & Analytics

Track your RAG pipeline performance:

```ruby
# With persistence
Desiru::Persistence[:module_executions].create_for_module(
  'RAGModule',
  { question: question },
  metadata: {
    retrieved_count: retrieved_docs.count,
    avg_relevance: retrieved_docs.map { |d| d[:score] }.sum / retrieved_docs.count
  }
)
```

## Next Steps

- Explore [Optimization](Optimizers-Overview) to improve retrieval and generation
- Add [Background Processing](Tutorial-Background-Jobs) for async RAG
- Implement [GraphQL API](Tutorial-GraphQL) for flexible querying
- Review [Production Guide](Production-Guide) for deployment best practices

## Resources

- [Example RAG implementation](https://github.com/obie/desiru/tree/main/examples/rag_retrieval.rb)
- [Vector database comparisons](https://github.com/obie/desiru/wiki/Vector-Databases)
- [Chunking strategies guide](https://github.com/obie/desiru/wiki/Chunking-Strategies)