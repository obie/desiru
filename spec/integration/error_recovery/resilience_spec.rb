require 'spec_helper'
require 'timeout'

RSpec.describe "Error Recovery and Resilience Integration", type: :integration do
  before do
    Desiru::Persistence::Database.setup!
    Desiru.configure do |config|
      config.default_model = instance_double(Desiru::RaixAdapter)
      config.redis = MockRedis.new
    end
  end

  after do
    Desiru::Persistence::Database.teardown!
  end

  describe "LLM provider failure handling" do
    let(:predict_module) do
      Desiru::Predict.new(
        signature: "question -> answer",
        retry_config: {
          max_attempts: 3,
          base_delay: 0.1,
          max_delay: 1,
          exponential_base: 2
        }
      )
    end

    it "retries on transient failures" do
      call_count = 0
      allow(predict_module).to receive(:call) do
        call_count += 1
        if call_count < 3
          raise Desiru::Models::APIError.new("Rate limit exceeded", status: 429)
        else
          { answer: "Success after retries" }
        end
      end

      result = predict_module.call(question: "What is Ruby?")

      expect(result[:answer]).to eq("Success after retries")
      expect(call_count).to eq(3)
    end

    it "falls back to secondary model on primary failure" do
      primary_model = instance_double(Desiru::RaixAdapter)
      secondary_model = instance_double(Desiru::RaixAdapter)

      Desiru.configure do |config|
        config.models = {
          primary: primary_model,
          fallback: secondary_model
        }
        config.default_model = :primary
      end

      module_with_fallback = Desiru::Predict.new(
        signature: "input -> output",
        model_fallback: :fallback
      )

      allow(primary_model).to receive(:complete)
        .and_raise(Desiru::Models::APIError, "Primary model unavailable")
      
      allow(secondary_model).to receive(:complete)
        .and_return("Fallback response")

      result = module_with_fallback.call(input: "test")

      expect(result[:output]).to eq("Fallback response")
      expect(primary_model).to have_received(:complete).once
      expect(secondary_model).to have_received(:complete).once
    end

    it "handles timeout with graceful degradation" do
      slow_module = Desiru::ChainOfThought.new(
        signature: "problem -> reasoning -> solution",
        timeout: 0.5
      )

      allow(slow_module).to receive(:call) do
        sleep 1 # Simulate slow response
        { reasoning: "...", solution: "42" }
      end

      expect {
        Timeout.timeout(0.6) do
          slow_module.call(problem: "Complex calculation")
        end
      }.to raise_error(Timeout::Error)
    end

    it "logs and persists error details for debugging" do
      error_module = Desiru::Predict.new(signature: "input -> output")
      
      allow(error_module).to receive(:call)
        .and_raise(Desiru::Module::ExecutionError, "Malformed response from LLM")

      expect {
        error_module.call(input: "test")
      }.to raise_error(Desiru::Module::ExecutionError)

      # Check error was persisted
      errors = Desiru::Persistence::Repositories::ModuleExecutionRepository.new
        .find_by_status("error")
      
      expect(errors).not_to be_empty
      expect(errors.first.error_message).to include("Malformed response")
    end
  end

  describe "database connection failures" do
    it "queues writes when database is unavailable" do
      # Simulate database failure
      allow(Desiru::Persistence::Database).to receive(:connected?).and_return(false)
      
      write_queue = []
      allow(Desiru::Persistence::WriteQueue).to receive(:enqueue) do |data|
        write_queue << data
      end

      module_with_persistence = Desiru::Predict.new(
        signature: "input -> output",
        persist: true
      )

      allow(module_with_persistence).to receive(:call).and_return({ output: "result" })

      # Should still work despite DB being down
      result = module_with_persistence.call(input: "test")
      expect(result[:output]).to eq("result")
      
      # But should queue the write
      expect(write_queue).not_to be_empty
      expect(write_queue.first[:module]).to eq("Predict")
    end

    it "processes queued writes when connection restored" do
      pending_writes = [
        { module: "Predict", input: { text: "test1" }, output: { result: "res1" } },
        { module: "ChainOfThought", input: { prob: "test2" }, output: { sol: "res2" } }
      ]

      # First, DB is down
      allow(Desiru::Persistence::Database).to receive(:connected?).and_return(false)
      
      # Queue some writes
      pending_writes.each do |write|
        Desiru::Persistence::WriteQueue.enqueue(write)
      end

      # Now DB comes back
      allow(Desiru::Persistence::Database).to receive(:connected?).and_return(true)
      
      # Process queue
      processed = Desiru::Persistence::WriteQueue.process!
      
      expect(processed).to eq(2)
      
      # Verify writes were persisted
      executions = Desiru::Persistence::Repositories::ModuleExecutionRepository.new.all
      expect(executions.size).to eq(2)
    end

    it "handles concurrent write conflicts" do
      repo = Desiru::Persistence::Repositories::OptimizationResultRepository.new
      
      # Simulate concurrent writes to same optimization
      threads = 5.times.map do |i|
        Thread.new do
          repo.create(
            module_name: "TestModule",
            optimizer_type: "BootstrapFewShot",
            metrics: { iteration: i, score: rand },
            examples: []
          )
        end
      end

      threads.each(&:join)

      # All writes should succeed
      results = repo.find_by_module("TestModule")
      expect(results.size).to eq(5)
    end
  end

  describe "async job failures" do
    it "retries failed jobs with exponential backoff" do
      job_class = Class.new(Desiru::Jobs::Base) do
        include Desiru::Jobs::Retriable
        
        retry_on Desiru::Module::ExecutionError, max_attempts: 3
        
        def perform(module_id, input)
          @attempt ||= 0
          @attempt += 1
          
          if @attempt < 3
            raise Desiru::Module::ExecutionError, "Temporary failure"
          else
            { success: true, attempts: @attempt }
          end
        end
      end

      job = job_class.new
      result = job.perform("test_module", { input: "data" })
      
      expect(result[:success]).to be true
      expect(result[:attempts]).to eq(3)
    end

    it "moves permanently failed jobs to dead letter queue" do
      failing_job = Class.new(Desiru::Jobs::Base) do
        def perform(*)
          raise "Unrecoverable error"
        end
      end

      job = failing_job.new
      
      expect {
        job.perform_with_error_handling("test", {})
      }.to raise_error(RuntimeError, "Unrecoverable error")

      # Check dead letter queue
      dead_jobs = Desiru::Persistence::Repositories::JobResultRepository.new
        .find_by_status("dead")
      
      expect(dead_jobs).not_to be_empty
      expect(dead_jobs.first.error_message).to include("Unrecoverable error")
    end

    it "handles Redis connection failures gracefully" do
      # Simulate Redis being down
      allow(Desiru.config.redis).to receive(:get).and_raise(Redis::CannotConnectError)
      
      async_module = Desiru::Predict.new(signature: "input -> output")
      
      # Should fall back to synchronous execution
      allow(async_module).to receive(:call).and_return({ output: "sync result" })
      
      result = async_module.call_async(input: "test")
      
      # Result should indicate fallback was used
      expect(result).to be_a(Desiru::AsyncResult)
      expect(result.fallback_mode?).to be true
    end
  end

  describe "circuit breaker pattern" do
    let(:module_with_circuit_breaker) do
      Desiru::Predict.new(
        signature: "input -> output",
        circuit_breaker: {
          failure_threshold: 3,
          timeout: 1,
          reset_timeout: 2
        }
      )
    end

    it "opens circuit after repeated failures" do
      failure_count = 0
      
      allow(module_with_circuit_breaker).to receive(:call) do
        failure_count += 1
        raise Desiru::Module::ExecutionError, "API Error"
      end

      # First 3 calls fail and trip the circuit
      3.times do
        expect {
          module_with_circuit_breaker.call(input: "test")
        }.to raise_error(Desiru::Module::ExecutionError)
      end

      # Circuit should now be open
      expect {
        module_with_circuit_breaker.call(input: "test")
      }.to raise_error(Desiru::CircuitBreakerOpenError)
      
      # Verify the module wasn't called when circuit was open
      expect(failure_count).to eq(3)
    end

    it "closes circuit after reset timeout" do
      # Trip the circuit
      3.times do
        allow(module_with_circuit_breaker).to receive(:call)
          .and_raise(Desiru::Module::ExecutionError)
        
        begin
          module_with_circuit_breaker.call(input: "fail")
        rescue Desiru::Module::ExecutionError
          # Expected
        end
      end

      # Circuit is now open
      expect {
        module_with_circuit_breaker.call(input: "test")
      }.to raise_error(Desiru::CircuitBreakerOpenError)

      # Wait for reset timeout
      sleep 2.1

      # Now it should work
      allow(module_with_circuit_breaker).to receive(:call)
        .and_return({ output: "success" })
      
      result = module_with_circuit_breaker.call(input: "test")
      expect(result[:output]).to eq("success")
    end
  end

  describe "cascading failure prevention" do
    let(:program) do
      Desiru::Program.new("Multi-stage Pipeline") do |prog|
        stage1 = Desiru::Predict.new(signature: "input -> intermediate")
        stage2 = Desiru::ChainOfThought.new(signature: "intermediate -> refined")
        stage3 = Desiru::Predict.new(signature: "refined -> final")
        
        prog.add_module(:stage1, stage1)
        prog.add_module(:stage2, stage2)
        prog.add_module(:stage3, stage3)
        
        prog.define_flow do |input|
          r1 = prog.modules[:stage1].call(input: input[:data])
          r2 = prog.modules[:stage2].call(intermediate: r1[:intermediate])
          prog.modules[:stage3].call(refined: r2[:refined])
        end
      end
    end

    it "stops execution on critical module failure" do
      # Stage 1 works
      allow(program.modules[:stage1]).to receive(:call)
        .and_return({ intermediate: "data" })
      
      # Stage 2 fails critically
      allow(program.modules[:stage2]).to receive(:call)
        .and_raise(Desiru::Module::CriticalError, "Cannot proceed")
      
      # Stage 3 should never be called
      allow(program.modules[:stage3]).to receive(:call)

      expect {
        program.call(data: "input")
      }.to raise_error(Desiru::Module::CriticalError)
      
      expect(program.modules[:stage3]).not_to have_received(:call)
    end

    it "provides partial results on non-critical failures" do
      allow(program.modules[:stage1]).to receive(:call)
        .and_return({ intermediate: "step1" })
      
      allow(program.modules[:stage2]).to receive(:call)
        .and_return({ refined: "step2" })
      
      allow(program.modules[:stage3]).to receive(:call)
        .and_raise(Desiru::Module::ExecutionError, "Output formatting error")

      program_with_partial = Desiru::Program.new("Partial Results") do |prog|
        prog.copy_from(program)
        prog.allow_partial_results = true
      end

      result = program_with_partial.call(data: "input")
      
      expect(result[:partial]).to be true
      expect(result[:completed_stages]).to eq([:stage1, :stage2])
      expect(result[:failed_stage]).to eq(:stage3)
      expect(result[:intermediate_results]).to include(
        stage1: { intermediate: "step1" },
        stage2: { refined: "step2" }
      )
    end
  end

  describe "webhook notification failures" do
    let(:webhook_url) { "https://example.com/webhook" }
    
    it "retries webhook notifications with backoff" do
      attempt = 0
      
      stub_request(:post, webhook_url).to_return do |request|
        attempt += 1
        if attempt < 3
          { status: 500, body: "Server Error" }
        else
          { status: 200, body: "OK" }
        end
      end

      notifier = Desiru::Jobs::WebhookNotifier.new
      result = notifier.perform(
        webhook_url,
        { event: "job_completed", job_id: "123" }
      )

      expect(result).to be true
      expect(attempt).to eq(3)
    end

    it "queues failed webhook for later delivery" do
      stub_request(:post, webhook_url)
        .to_return(status: 500, body: "Persistent Error")
        .times(5) # All retries fail

      notifier = Desiru::Jobs::WebhookNotifier.new
      
      expect {
        notifier.perform(webhook_url, { event: "test" })
      }.to raise_error(Desiru::Jobs::WebhookDeliveryError)

      # Check that webhook was queued for retry
      failed_webhooks = Desiru::Persistence::Repositories::JobResultRepository.new
        .find_by_job_type("webhook_retry")
      
      expect(failed_webhooks).not_to be_empty
      expect(failed_webhooks.first.metadata["url"]).to eq(webhook_url)
    end
  end

  describe "rate limiting and throttling" do
    it "handles rate limit errors across modules" do
      rate_limiter = Desiru::RateLimiter.new(
        max_requests: 2,
        window: 1.second,
        strategy: :sliding_window
      )

      Desiru.configure do |config|
        config.rate_limiter = rate_limiter
      end

      fast_module = Desiru::Predict.new(signature: "input -> output")
      allow(fast_module).to receive(:call).and_return({ output: "result" })

      # First two calls succeed
      2.times do |i|
        result = fast_module.call(input: "test#{i}")
        expect(result[:output]).to eq("result")
      end

      # Third call should be rate limited
      expect {
        fast_module.call(input: "test3")
      }.to raise_error(Desiru::RateLimitError)

      # Wait for window to slide
      sleep 1.1

      # Now it should work again
      result = fast_module.call(input: "test4")
      expect(result[:output]).to eq("result")
    end

    it "implements adaptive throttling based on error rates" do
      adaptive_module = Desiru::Predict.new(
        signature: "input -> output",
        adaptive_throttling: true
      )

      error_count = 0
      allow(adaptive_module).to receive(:call) do
        error_count += 1
        if error_count <= 5
          raise Desiru::Models::APIError.new("Rate limit", status: 429)
        else
          { output: "success" }
        end
      end

      # Module should automatically slow down after errors
      start_time = Time.now
      
      expect {
        6.times { adaptive_module.call(input: "test") rescue nil }
      }.to change { Time.now - start_time }.by_at_least(1.0)
    end
  end
end