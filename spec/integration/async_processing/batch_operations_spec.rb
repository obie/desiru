require 'spec_helper'
require 'sidekiq/testing'

RSpec.describe "Batch Operations Integration", type: :integration do
  before do
    Sidekiq::Testing.inline!
    Desiru::Persistence::Database.setup!
    
    Desiru.configure do |config|
      config.default_model = instance_double(Desiru::RaixAdapter)
      config.redis = MockRedis.new
    end
  end

  after do
    Desiru::Persistence::Database.teardown!
    Sidekiq::Testing.disable!
  end

  describe "batch module execution" do
    let(:predict_module) do
      Desiru::Predict.new(
        signature: "text -> sentiment",
        examples: [
          { text: "I love this!", sentiment: "positive" },
          { text: "This is terrible", sentiment: "negative" }
        ]
      )
    end

    let(:inputs) do
      [
        { text: "Amazing product!" },
        { text: "Worst experience ever" },
        { text: "It's okay I guess" },
        { text: "Absolutely fantastic!" },
        { text: "Complete disaster" }
      ]
    end

    it "processes multiple inputs concurrently" do
      responses = [
        { sentiment: "positive" },
        { sentiment: "negative" },
        { sentiment: "neutral" },
        { sentiment: "positive" },
        { sentiment: "negative" }
      ]

      allow(predict_module).to receive(:call).and_return(*responses)

      batch_result = predict_module.batch_call(inputs)

      expect(batch_result).to be_a(Desiru::BatchResult)
      expect(batch_result.results.size).to eq(5)
      expect(batch_result.results.map { |r| r[:sentiment] }).to eq(
        ["positive", "negative", "neutral", "positive", "negative"]
      )
      expect(batch_result.success?).to be true
    end

    it "handles partial failures in batch" do
      call_count = 0
      allow(predict_module).to receive(:call) do
        call_count += 1
        if call_count == 3
          raise Desiru::Module::ExecutionError, "API error"
        else
          { sentiment: "positive" }
        end
      end

      batch_result = predict_module.batch_call(inputs)

      expect(batch_result.results.size).to eq(5)
      expect(batch_result.success?).to be false
      expect(batch_result.failed_indices).to eq([2])
      expect(batch_result.errors[2]).to include("API error")
      
      # Other results should still be present
      successful_results = batch_result.results.reject.with_index { |_, i| i == 2 }
      expect(successful_results.all? { |r| r[:sentiment] == "positive" }).to be true
    end

    it "persists batch execution results" do
      allow(predict_module).to receive(:call).and_return({ sentiment: "positive" })

      batch_result = predict_module.batch_call(inputs)

      job_results = Desiru::Persistence::Repositories::JobResultRepository.new.all
      expect(job_results.size).to eq(1)
      expect(job_results.first.job_type).to eq("batch")
      expect(job_results.first.metadata["input_count"]).to eq(5)
      expect(job_results.first.status).to eq("completed")
    end
  end

  describe "async batch processing" do
    let(:cot_module) do
      Desiru::ChainOfThought.new(
        signature: "problem -> reasoning -> solution"
      )
    end

    let(:problems) do
      [
        { problem: "Calculate 15% tip on $80" },
        { problem: "How many hours in 3 days?" },
        { problem: "Convert 5 miles to kilometers" }
      ]
    end

    it "processes batch asynchronously with status tracking" do
      allow(cot_module).to receive(:call).and_return(
        { reasoning: "Step by step...", solution: "Answer" }
      )

      batch_job = cot_module.batch_call_async(problems)

      expect(batch_job).to be_a(Desiru::AsyncResult)
      expect(batch_job.status).to eq("pending")

      # In inline mode, job executes immediately
      batch_job.wait(timeout: 5)

      expect(batch_job.status).to eq("completed")
      expect(batch_job.result).to be_a(Desiru::BatchResult)
      expect(batch_job.result.results.size).to eq(3)
    end

    it "provides progress updates during batch processing" do
      progress_updates = []
      
      allow(cot_module).to receive(:call) do |input|
        sleep 0.1 # Simulate processing time
        { reasoning: "Processed", solution: "Done" }
      end

      batch_job = cot_module.batch_call_async(
        problems,
        on_progress: ->(completed, total) { progress_updates << [completed, total] }
      )

      batch_job.wait(timeout: 10)

      expect(progress_updates).not_to be_empty
      expect(progress_updates.last).to eq([3, 3])
    end
  end

  describe "batch optimization" do
    let(:module_to_optimize) do
      Desiru::Predict.new(signature: "question -> answer")
    end

    let(:optimizer) do
      Desiru::Optimizers::BootstrapFewShot.new(
        module: module_to_optimize,
        metric: :exact_match
      )
    end

    let(:training_batches) do
      [
        [
          { question: "What is 2+2?", answer: "4" },
          { question: "What is 3+3?", answer: "6" }
        ],
        [
          { question: "Capital of France?", answer: "Paris" },
          { question: "Capital of Spain?", answer: "Madrid" }
        ],
        [
          { question: "Who wrote Hamlet?", answer: "Shakespeare" },
          { question: "Who painted Starry Night?", answer: "Van Gogh" }
        ]
      ]
    end

    it "optimizes using batched training data" do
      allow(module_to_optimize).to receive(:call).and_return({ answer: "test" })

      batch_optimization = optimizer.optimize_batch(
        training_batches: training_batches,
        batch_size: 2
      )

      expect(batch_optimization).to be_a(Desiru::Module)
      expect(batch_optimization.examples.size).to be > 0
      
      # Verify batched processing was used
      expect(module_to_optimize).to have_received(:call).at_least(6).times
    end
  end

  describe "complex batch workflows" do
    let(:program) do
      Desiru::Program.new("Batch Text Processor") do |prog|
        sentiment = Desiru::Predict.new(signature: "text -> sentiment")
        summary = Desiru::ChainOfThought.new(signature: "text -> summary")
        classify = Desiru::Predict.new(signature: "text -> category")
        
        prog.add_module(:sentiment, sentiment)
        prog.add_module(:summary, summary)
        prog.add_module(:classify, classify)
        
        prog.define_flow do |input|
          # Process all modules in parallel
          results = prog.parallel_execute(input[:text]) do |text, modules|
            {
              sentiment: modules[:sentiment].call(text: text),
              summary: modules[:summary].call(text: text),
              category: modules[:classify].call(text: text)
            }
          end
          
          {
            text: input[:text],
            analysis: results
          }
        end
      end
    end

    let(:texts) do
      [
        { text: "The new iPhone is amazing! Best purchase ever." },
        { text: "Climate change requires immediate action from all nations." },
        { text: "The restaurant food was cold and service was slow." }
      ]
    end

    it "processes multiple texts through multiple modules efficiently" do
      # Mock responses for each module
      allow(program.modules[:sentiment]).to receive(:call).and_return(
        { sentiment: "positive" },
        { sentiment: "neutral" },
        { sentiment: "negative" }
      )
      
      allow(program.modules[:summary]).to receive(:call).and_return(
        { summary: "Positive review of iPhone" },
        { summary: "Climate change urgency" },
        { summary: "Poor restaurant experience" }
      )
      
      allow(program.modules[:classify]).to receive(:call).and_return(
        { category: "technology" },
        { category: "environment" },
        { category: "food" }
      )

      batch_result = program.batch_call(texts)

      expect(batch_result.results.size).to eq(3)
      
      first_result = batch_result.results[0]
      expect(first_result[:analysis][:sentiment][:sentiment]).to eq("positive")
      expect(first_result[:analysis][:summary][:summary]).to include("iPhone")
      expect(first_result[:analysis][:category][:category]).to eq("technology")
    end

    it "handles rate limiting across batch operations" do
      rate_limiter = Desiru::RateLimiter.new(
        max_requests: 5,
        window: 1.second
      )

      Desiru.configure do |config|
        config.rate_limiter = rate_limiter
      end

      start_time = Time.now
      
      # Process 10 items with rate limit of 5 per second
      large_batch = texts * 4 # 12 items total
      
      allow(program.modules[:sentiment]).to receive(:call).and_return({ sentiment: "neutral" })
      allow(program.modules[:summary]).to receive(:call).and_return({ summary: "text" })
      allow(program.modules[:classify]).to receive(:call).and_return({ category: "general" })

      batch_result = program.batch_call(large_batch)

      elapsed_time = Time.now - start_time
      
      # Should take at least 2 seconds due to rate limiting
      expect(elapsed_time).to be >= 2.0
      expect(batch_result.results.size).to eq(12)
    end
  end

  describe "batch processing with webhooks" do
    let(:webhook_url) { "https://example.com/webhook" }
    let(:module_with_webhook) do
      Desiru::Predict.new(
        signature: "input -> output",
        webhook_url: webhook_url
      )
    end

    it "sends webhook notifications for batch completion" do
      stub_request(:post, webhook_url)
        .to_return(status: 200, body: "OK")

      allow(module_with_webhook).to receive(:call).and_return({ output: "result" })

      batch_result = module_with_webhook.batch_call(
        [{ input: "test1" }, { input: "test2" }],
        notify_on_completion: true
      )

      expect(batch_result.success?).to be true
      
      expect(WebMock).to have_requested(:post, webhook_url)
        .with(body: hash_including(
          "status" => "completed",
          "batch_size" => 2,
          "success_count" => 2
        ))
    end
  end
end