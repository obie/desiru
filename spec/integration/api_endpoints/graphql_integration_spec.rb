require 'spec_helper'
require 'rack/test'

RSpec.describe "GraphQL API Integration", type: :integration do
  include Rack::Test::Methods

  def app
    Desiru::GraphQL::App
  end

  before do
    Desiru::Persistence::Database.setup!
    
    Desiru.configure do |config|
      config.default_model = instance_double(Desiru::RaixAdapter)
    end

    # Register modules for GraphQL schema
    Desiru::Registry.register("sentiment_analyzer", 
      Desiru::Predict.new(
        signature: "text -> sentiment, confidence:float",
        examples: [
          { text: "I love it!", sentiment: "positive", confidence: 0.95 }
        ]
      )
    )

    Desiru::Registry.register("text_summarizer",
      Desiru::ChainOfThought.new(
        signature: "article -> summary, key_points:list"
      )
    )

    Desiru::Registry.register("qa_system",
      Desiru::Program.new("Q&A") do |prog|
        retriever = Desiru::Retrieve.new(k: 5)
        answerer = Desiru::Predict.new(signature: "question, context -> answer")
        
        prog.add_module(:retrieve, retriever)
        prog.add_module(:answer, answerer)
        
        prog.define_flow do |input|
          context = prog.modules[:retrieve].call(query: input[:question])
          prog.modules[:answer].call(
            question: input[:question],
            context: context[:results]
          )
        end
      end
    )
  end

  after do
    Desiru::Registry.clear!
    Desiru::Persistence::Database.teardown!
  end

  describe "module execution via GraphQL" do
    it "executes a simple predict module" do
      allow(Desiru::Registry.get("sentiment_analyzer")).to receive(:call)
        .and_return({ sentiment: "positive", confidence: 0.92 })

      query = <<~GRAPHQL
        query AnalyzeSentiment($text: String!) {
          sentiment_analyzer(text: $text) {
            sentiment
            confidence
          }
        }
      GRAPHQL

      post '/graphql', 
        query: query,
        variables: { text: "This is amazing!" }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      expect(result["data"]["sentiment_analyzer"]["sentiment"]).to eq("positive")
      expect(result["data"]["sentiment_analyzer"]["confidence"]).to eq(0.92)
    end

    it "executes a module with complex output types" do
      allow(Desiru::Registry.get("text_summarizer")).to receive(:call)
        .and_return({
          summary: "A brief overview of the article",
          key_points: ["Point 1", "Point 2", "Point 3"]
        })

      query = <<~GRAPHQL
        query SummarizeText($article: String!) {
          text_summarizer(article: $article) {
            summary
            key_points
          }
        }
      GRAPHQL

      post '/graphql',
        query: query,
        variables: { article: "Long article text..." }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      expect(result["data"]["text_summarizer"]["summary"]).to include("brief overview")
      expect(result["data"]["text_summarizer"]["key_points"]).to eq(["Point 1", "Point 2", "Point 3"])
    end

    it "handles module execution errors gracefully" do
      allow(Desiru::Registry.get("sentiment_analyzer")).to receive(:call)
        .and_raise(Desiru::Module::ExecutionError, "LLM API timeout")

      query = <<~GRAPHQL
        query AnalyzeSentiment($text: String!) {
          sentiment_analyzer(text: $text) {
            sentiment
          }
        }
      GRAPHQL

      post '/graphql',
        query: query,
        variables: { text: "Test" }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      expect(result["errors"]).to be_present
      expect(result["errors"].first["message"]).to include("LLM API timeout")
    end
  end

  describe "batch queries" do
    it "executes multiple modules in a single query" do
      allow(Desiru::Registry.get("sentiment_analyzer")).to receive(:call)
        .and_return({ sentiment: "positive", confidence: 0.9 })
      
      allow(Desiru::Registry.get("text_summarizer")).to receive(:call)
        .and_return({ 
          summary: "Brief summary", 
          key_points: ["Main point"] 
        })

      query = <<~GRAPHQL
        query AnalyzeText($text: String!) {
          sentiment: sentiment_analyzer(text: $text) {
            sentiment
            confidence
          }
          summary: text_summarizer(article: $text) {
            summary
            key_points
          }
        }
      GRAPHQL

      post '/graphql',
        query: query,
        variables: { text: "Analyze this text" }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      expect(result["data"]["sentiment"]["sentiment"]).to eq("positive")
      expect(result["data"]["summary"]["summary"]).to eq("Brief summary")
    end

    it "uses DataLoader for efficient batch loading" do
      # Create multiple sentiment analysis requests
      queries = Array.new(5) do |i|
        {
          query: <<~GRAPHQL,
            query {
              sentiment_analyzer(text: "Text #{i}") {
                sentiment
              }
            }
          GRAPHQL
        }
      end

      # Should batch load instead of N+1 queries
      expect(Desiru::Registry.get("sentiment_analyzer")).to receive(:batch_call).once
        .and_return(
          Desiru::BatchResult.new(
            results: Array.new(5) { { sentiment: "neutral" } },
            errors: {}
          )
        )

      post '/graphql',
        queries.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      results = JSON.parse(last_response.body)
      expect(results).to be_an(Array)
      expect(results.size).to eq(5)
    end
  end

  describe "async execution via GraphQL" do
    it "initiates async module execution" do
      job = instance_double(Desiru::AsyncResult, id: "job-123", status: "pending")
      allow(Desiru::Registry.get("text_summarizer")).to receive(:call_async)
        .and_return(job)

      mutation = <<~GRAPHQL
        mutation SummarizeAsync($article: String!) {
          text_summarizer_async(article: $article) {
            jobId
            status
          }
        }
      GRAPHQL

      post '/graphql',
        query: mutation,
        variables: { article: "Long text to summarize" }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      expect(result["data"]["text_summarizer_async"]["jobId"]).to eq("job-123")
      expect(result["data"]["text_summarizer_async"]["status"]).to eq("pending")
    end

    it "queries async job status" do
      job_result = {
        summary: "Completed summary",
        key_points: ["Point A", "Point B"]
      }

      # Mock job repository
      job = double(
        id: "job-123",
        status: "completed",
        result: job_result,
        error: nil
      )
      
      allow_any_instance_of(Desiru::Persistence::Repositories::JobResultRepository)
        .to receive(:find).with("job-123").and_return(job)

      query = <<~GRAPHQL
        query GetJobStatus($jobId: ID!) {
          job(id: $jobId) {
            id
            status
            result
            error
          }
        }
      GRAPHQL

      post '/graphql',
        query: query,
        variables: { jobId: "job-123" }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      expect(result["data"]["job"]["status"]).to eq("completed")
      expect(result["data"]["job"]["result"]).to eq(job_result.stringify_keys)
    end
  end

  describe "GraphQL subscriptions" do
    it "subscribes to module execution updates" do
      # GraphQL subscriptions require WebSocket support
      # This test simulates the subscription flow
      
      subscription = <<~GRAPHQL
        subscription OnModuleExecution($moduleId: ID!) {
          moduleExecution(moduleId: $moduleId) {
            status
            progress
            result
          }
        }
      GRAPHQL

      # Simulate subscription setup
      expect {
        post '/graphql',
          query: subscription,
          variables: { moduleId: "sentiment_analyzer" }.to_json,
          'CONTENT_TYPE' => 'application/json'
      }.not_to raise_error

      # In a real implementation, this would establish a WebSocket connection
      # and stream updates as the module executes
    end
  end

  describe "GraphQL introspection" do
    it "provides schema introspection" do
      query = <<~GRAPHQL
        {
          __schema {
            types {
              name
              kind
            }
          }
        }
      GRAPHQL

      post '/graphql',
        query: query,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      type_names = result["data"]["__schema"]["types"].map { |t| t["name"] }
      expect(type_names).to include("Query", "Mutation", "String", "Float")
    end

    it "provides module-specific type information" do
      query = <<~GRAPHQL
        {
          __type(name: "SentimentAnalyzerOutput") {
            name
            fields {
              name
              type {
                name
                kind
              }
            }
          }
        }
      GRAPHQL

      post '/graphql',
        query: query,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      type_info = result["data"]["__type"]
      expect(type_info["name"]).to eq("SentimentAnalyzerOutput")
      
      field_names = type_info["fields"].map { |f| f["name"] }
      expect(field_names).to include("sentiment", "confidence")
    end
  end

  describe "GraphQL with caching" do
    before do
      Desiru.configure do |config|
        config.cache = Desiru::Cache.new
      end
    end

    it "caches repeated queries" do
      allow(Desiru::Registry.get("sentiment_analyzer")).to receive(:call)
        .once  # Should only be called once due to caching
        .and_return({ sentiment: "positive", confidence: 0.95 })

      query = <<~GRAPHQL
        query AnalyzeSentiment($text: String!) {
          sentiment_analyzer(text: $text) {
            sentiment
            confidence
          }
        }
      GRAPHQL

      # First request
      post '/graphql',
        query: query,
        variables: { text: "Cacheable text" }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      first_result = JSON.parse(last_response.body)

      # Second request (should hit cache)
      post '/graphql',
        query: query,
        variables: { text: "Cacheable text" }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      second_result = JSON.parse(last_response.body)

      expect(first_result).to eq(second_result)
      expect(Desiru::Registry.get("sentiment_analyzer")).to have_received(:call).once
    end
  end

  describe "complex program execution via GraphQL" do
    it "executes a multi-module program" do
      # Mock retriever
      allow_any_instance_of(Desiru::Retrieve).to receive(:call)
        .and_return({ 
          results: ["Context 1", "Context 2", "Context 3"] 
        })

      # Mock answerer
      allow_any_instance_of(Desiru::Predict).to receive(:call)
        .and_return({ 
          answer: "The answer based on retrieved context" 
        })

      query = <<~GRAPHQL
        query AskQuestion($question: String!) {
          qa_system(question: $question) {
            answer
          }
        }
      GRAPHQL

      post '/graphql',
        query: query,
        variables: { question: "What is Ruby?" }.to_json,
        'CONTENT_TYPE' => 'application/json'

      expect(last_response).to be_ok
      result = JSON.parse(last_response.body)
      
      expect(result["data"]["qa_system"]["answer"]).to include("answer based on retrieved context")
    end
  end
end