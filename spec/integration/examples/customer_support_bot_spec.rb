require 'spec_helper'

RSpec.describe "Customer Support Bot Integration Example", type: :integration do
  include IntegrationHelpers

  let(:knowledge_base) do
    [
      "Our return policy allows returns within 30 days of purchase.",
      "Shipping takes 3-5 business days for standard delivery.",
      "Premium members get free shipping on all orders.",
      "Contact support@example.com for urgent issues.",
      "Our business hours are Monday-Friday 9AM-5PM EST."
    ]
  end

  let(:support_bot) do
    Desiru::Program.new("Customer Support Bot") do |prog|
      # Intent classifier
      classifier = Desiru::Predict.new(
        signature: "query -> intent",
        examples: [
          { query: "How do I return an item?", intent: "returns" },
          { query: "When will my order arrive?", intent: "shipping" },
          { query: "What are your hours?", intent: "hours" },
          { query: "I need help with my account", intent: "account" }
        ]
      )

      # Knowledge retriever
      retriever = Desiru::Retrieve.new(
        k: 3,
        corpus: knowledge_base
      )

      # Response generator with chain of thought
      responder = Desiru::ChainOfThought.new(
        signature: "query, intent, context -> reasoning -> response",
        examples: [
          {
            query: "Can I return something I bought last month?",
            intent: "returns",
            context: ["Return policy: 30 days"],
            reasoning: "Customer bought item last month. Our return policy is 30 days. Need to check exact purchase date.",
            response: "Our return policy allows returns within 30 days of purchase. Could you provide your order date so I can check if it's still within the return window?"
          }
        ]
      )

      # Sentiment analyzer for escalation
      sentiment = Desiru::Predict.new(
        signature: "message -> sentiment, escalate:bool",
        examples: [
          { message: "This is unacceptable!", sentiment: "angry", escalate: true },
          { message: "Thanks for your help", sentiment: "positive", escalate: false },
          { message: "I'm really frustrated", sentiment: "frustrated", escalate: true }
        ]
      )

      prog.add_module(:classifier, classifier)
      prog.add_module(:retriever, retriever)
      prog.add_module(:responder, responder)
      prog.add_module(:sentiment, sentiment)

      prog.define_flow do |input|
        # Analyze sentiment first
        sentiment_result = prog.modules[:sentiment].call(message: input[:query])
        
        # Classify intent
        intent_result = prog.modules[:classifier].call(query: input[:query])
        
        # Retrieve relevant context
        context_result = prog.modules[:retriever].call(query: input[:query])
        
        # Generate response
        response_result = prog.modules[:responder].call(
          query: input[:query],
          intent: intent_result[:intent],
          context: context_result[:results]
        )
        
        {
          query: input[:query],
          intent: intent_result[:intent],
          response: response_result[:response],
          sentiment: sentiment_result[:sentiment],
          should_escalate: sentiment_result[:escalate],
          conversation_id: input[:conversation_id] || SecureRandom.uuid
        }
      end
    end
  end

  before do
    # Set up test models
    stub_model_responses(
      # Classifier responses
      { intent: "returns" },
      { intent: "shipping" },
      { intent: "account" },
      
      # Sentiment responses  
      { sentiment: "neutral", escalate: false },
      { sentiment: "frustrated", escalate: true },
      { sentiment: "positive", escalate: false },
      
      # Responder responses
      { 
        reasoning: "Customer asking about returns. Policy is 30 days.",
        response: "You can return items within 30 days of purchase. Would you like me to help you start a return?"
      },
      {
        reasoning: "Customer asking about shipping status.",
        response: "Standard shipping takes 3-5 business days. Can you provide your order number?"
      },
      {
        reasoning: "Customer needs account help and seems frustrated.",
        response: "I understand your frustration. Let me connect you with a specialist who can help with your account."
      }
    )

    # Mock retriever
    allow(support_bot.modules[:retriever]).to receive(:call) do |args|
      relevant = knowledge_base.select { |kb| kb.downcase.include?(args[:query].downcase.split.first) }
      { results: relevant.take(3) }
    end
  end

  describe "basic conversation flow" do
    it "handles a simple return query" do
      result = support_bot.call(query: "How can I return my order?")

      expect(result[:intent]).to eq("returns")
      expect(result[:response]).to include("30 days")
      expect(result[:should_escalate]).to be false
      expect(result[:conversation_id]).to be_present
    end

    it "identifies frustrated customers for escalation" do
      result = support_bot.call(
        query: "I've been trying to log in for hours and nothing works!",
        conversation_id: "existing-123"
      )

      expect(result[:sentiment]).to eq("frustrated")
      expect(result[:should_escalate]).to be true
      expect(result[:response]).to include("specialist")
      expect(result[:conversation_id]).to eq("existing-123")
    end
  end

  describe "conversation persistence" do
    it "maintains conversation context across interactions" do
      conversation_id = SecureRandom.uuid
      
      # First message
      result1 = support_bot.call(
        query: "When will my order arrive?",
        conversation_id: conversation_id
      )

      # Check persistence
      executions = find_module_executions
      expect(executions.size).to be > 0
      
      conversation_data = executions.select do |e| 
        e.metadata&.dig("conversation_id") == conversation_id
      end
      expect(conversation_data).not_to be_empty

      # Second message in same conversation
      result2 = support_bot.call(
        query: "What if I'm not home?",
        conversation_id: conversation_id
      )

      expect(result2[:conversation_id]).to eq(conversation_id)
    end
  end

  describe "async conversation handling" do
    it "processes multiple customer queries concurrently" do
      queries = [
        { query: "How do I return this?" },
        { query: "Where is my package?" },
        { query: "I can't access my account" }
      ]

      with_inline_jobs do
        batch_result = support_bot.batch_call_async(queries)
        wait_for_job(batch_result)

        expect(batch_result.status).to eq("completed")
        expect(batch_result.result.results.size).to eq(3)
        
        # Each should have a unique conversation ID
        conversation_ids = batch_result.result.results.map { |r| r[:conversation_id] }
        expect(conversation_ids.uniq.size).to eq(3)
      end
    end
  end

  describe "optimization workflow" do
    let(:training_conversations) do
      [
        { 
          query: "I want to return my shoes",
          expected_intent: "returns",
          expected_response_includes: ["return", "30 days"]
        },
        {
          query: "When does shipping usually take?",
          expected_intent: "shipping", 
          expected_response_includes: ["3-5", "business days"]
        },
        {
          query: "This is ridiculous! I want a refund NOW!",
          expected_intent: "returns",
          expected_escalate: true
        }
      ]
    end

    it "improves bot responses through optimization" do
      optimizer = create_test_optimizer(
        support_bot,
        metric: lambda do |prediction, expected|
          score = 0.0
          score += 0.5 if prediction[:intent] == expected[:expected_intent]
          score += 0.5 if expected[:expected_escalate].nil? || 
                         prediction[:should_escalate] == expected[:expected_escalate]
          score
        end
      )

      # Mock training data format
      formatted_training = training_conversations.map do |conv|
        {
          query: conv[:query],
          intent: conv[:expected_intent],
          should_escalate: conv[:expected_escalate] || false
        }
      end

      mock_optimization_run(optimizer, expected_score: 0.85)
      
      optimized_bot = optimizer.optimize(
        training_data: formatted_training,
        validation_data: formatted_training.take(1)
      )

      expect(optimized_bot).to be_a(Desiru::Program)
      
      # Check optimization was persisted
      optimization_results = Desiru::Persistence::Repositories::OptimizationResultRepository.new.all
      expect(optimization_results).not_to be_empty
      expect(optimization_results.last.module_name).to eq("Customer Support Bot")
    end
  end

  describe "real-world error scenarios" do
    it "handles API failures gracefully" do
      # Simulate classifier failing
      inject_transient_errors(support_bot.modules[:classifier], :call, error_count: 2)
      
      # Should retry and eventually succeed
      result = support_bot.call(query: "Help with return")
      expect(result[:response]).to be_present
    end

    it "falls back when retriever fails" do
      allow(support_bot.modules[:retriever]).to receive(:call)
        .and_raise(Desiru::Module::ExecutionError, "Vector DB unavailable")

      # Should still generate a response without context
      result = support_bot.call(query: "What's your return policy?")
      
      expect(result[:response]).to be_present
      expect(result[:intent]).to eq("returns")
    end

    it "rate limits during high traffic" do
      with_rate_limiter(max_requests: 5, window: 1.second) do
        # Simulate burst of requests
        results = []
        errors = []
        
        10.times do |i|
          begin
            results << support_bot.call(query: "Query #{i}")
          rescue Desiru::RateLimitError => e
            errors << e
          end
        end

        expect(results.size).to eq(5)
        expect(errors.size).to eq(5)
      end
    end
  end

  describe "monitoring and analytics" do
    it "tracks conversation metrics" do
      # Process several conversations
      conversations = [
        { query: "Return help", expected_intent: "returns" },
        { query: "Angry about shipping!", expected_escalate: true },
        { query: "Thanks for the help", expected_sentiment: "positive" }
      ]

      conversations.each do |conv|
        support_bot.call(query: conv[:query])
      end

      # Analyze metrics
      executions = find_module_executions(module_name: "Predict")
      
      intents = executions
        .select { |e| e.input_data["signature"]&.include?("intent") }
        .map { |e| e.output_data["intent"] }
      
      expect(intents).to include("returns")

      escalations = executions
        .select { |e| e.output_data["escalate"] == true }
      
      expect(escalations.size).to be >= 1
    end
  end

  describe "integration with external systems" do
    let(:crm_webhook) { "https://crm.example.com/conversations" }
    let(:escalation_webhook) { "https://support.example.com/escalate" }

    before do
      Desiru.configure do |config|
        config.webhooks = {
          conversation_complete: crm_webhook,
          escalation_required: escalation_webhook
        }
      end
    end

    it "notifies CRM of completed conversations" do
      stub_webhook(crm_webhook)
      
      result = support_bot.call(query: "How do returns work?")
      
      # Trigger webhook
      Desiru::Jobs::WebhookNotifier.new.perform(
        crm_webhook,
        {
          conversation_id: result[:conversation_id],
          intent: result[:intent],
          resolved: !result[:should_escalate]
        }
      )

      expect(WebMock).to have_requested(:post, crm_webhook)
        .with(body: hash_including("conversation_id", "intent"))
    end

    it "triggers escalation webhook for frustrated customers" do
      stub_webhook(escalation_webhook)
      
      result = support_bot.call(query: "This is completely unacceptable!")
      
      if result[:should_escalate]
        Desiru::Jobs::WebhookNotifier.new.perform(
          escalation_webhook,
          {
            conversation_id: result[:conversation_id],
            sentiment: result[:sentiment],
            query: result[:query]
          }
        )
      end

      expect(WebMock).to have_requested(:post, escalation_webhook)
    end
  end
end