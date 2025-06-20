# frozen_string_literal: true

module IntegrationHelpers
  # Database helpers
  def setup_test_database
    Desiru::Persistence::Database.setup!
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.start
  end

  def cleanup_test_database
    DatabaseCleaner.clean
    Desiru::Persistence::Database.teardown!
  end

  # Module creation helpers
  def create_test_predict_module(signature: "input -> output", examples: [])
    Desiru::Predict.new(
      signature: signature,
      examples: examples,
      model: test_model
    )
  end

  def create_test_cot_module(signature: "question -> reasoning -> answer", examples: [])
    Desiru::ChainOfThought.new(
      signature: signature,
      examples: examples,
      model: test_model
    )
  end

  def create_test_react_module(signature: "task -> result", tools: [])
    Desiru::ReAct.new(
      signature: signature,
      tools: tools,
      model: test_model
    )
  end

  def create_test_retrieve_module(k: 5)
    Desiru::Retrieve.new(
      k: k,
      embeddings_model: test_embeddings_model
    )
  end

  # Model helpers
  def test_model
    @test_model ||= instance_double(Desiru::RaixAdapter)
  end

  def test_embeddings_model
    @test_embeddings_model ||= instance_double(Desiru::EmbeddingsModel)
  end

  def stub_model_response(response)
    allow(test_model).to receive(:complete).and_return(response)
  end

  def stub_model_responses(*responses)
    allow(test_model).to receive(:complete).and_return(*responses)
  end

  def stub_embeddings_response(embeddings)
    allow(test_embeddings_model).to receive(:embed).and_return(embeddings)
  end

  # Program helpers
  def create_test_program(name: "Test Program", &block)
    Desiru::Program.new(name, &block)
  end

  def create_pipeline_program(*modules)
    Desiru::Program.new("Pipeline") do |prog|
      modules.each_with_index do |mod, i|
        prog.add_module("stage#{i}", mod)
      end
      
      prog.define_flow do |input|
        result = input
        modules.each_with_index do |_, i|
          result = prog.modules["stage#{i}"].call(result)
        end
        result
      end
    end
  end

  # Async helpers
  def wait_for_job(job, timeout: 5)
    Timeout.timeout(timeout) do
      while job.status == "pending" || job.status == "processing"
        sleep 0.1
      end
    end
    job
  end

  def wait_for_all_jobs(jobs, timeout: 10)
    Timeout.timeout(timeout) do
      jobs.each { |job| wait_for_job(job) }
    end
    jobs
  end

  def with_inline_jobs
    previous = Sidekiq::Testing.current_mode
    Sidekiq::Testing.inline!
    yield
  ensure
    Sidekiq::Testing.send("#{previous}!")
  end

  # Cache helpers
  def with_cache
    cache = Desiru::Cache.new
    Desiru.configure { |c| c.cache = cache }
    yield cache
  ensure
    cache.clear
    Desiru.configure { |c| c.cache = nil }
  end

  def with_test_cache_data(data = {})
    with_cache do |cache|
      data.each { |key, value| cache.set(key, value) }
      yield cache
    end
  end

  # API helpers
  def json_response
    JSON.parse(last_response.body)
  end

  def post_json(path, data)
    post path, data.to_json, 'CONTENT_TYPE' => 'application/json'
  end

  def get_json(path, params = {})
    get path, params, 'CONTENT_TYPE' => 'application/json'
  end

  # Training data helpers
  def generate_training_data(count, template)
    Array.new(count) do |i|
      template.transform_values do |v|
        v.is_a?(String) ? v.gsub("{i}", i.to_s) : v
      end
    end
  end

  def create_classification_data(categories)
    categories.flat_map do |category, examples|
      examples.map { |text| { text: text, category: category } }
    end
  end

  # Optimization helpers
  def create_test_optimizer(module_to_optimize, **options)
    Desiru::Optimizers::BootstrapFewShot.new(
      module: module_to_optimize,
      metric: :exact_match,
      num_candidates: 2,
      max_iterations: 2,
      **options
    )
  end

  def mock_optimization_run(optimizer, expected_score: 0.8)
    allow(optimizer).to receive(:evaluate).and_return(expected_score)
    allow(optimizer).to receive(:select_examples).and_return([])
  end

  # Error injection helpers
  def inject_transient_errors(object, method, error_count: 2)
    call_count = 0
    original_method = object.method(method)
    
    allow(object).to receive(method) do |*args|
      call_count += 1
      if call_count <= error_count
        raise Desiru::Module::ExecutionError, "Transient error #{call_count}"
      else
        original_method.call(*args)
      end
    end
  end

  def inject_rate_limit_errors(object, method, limit: 3)
    call_count = 0
    
    allow(object).to receive(method) do |*args|
      call_count += 1
      if call_count > limit
        raise Desiru::Models::APIError.new("Rate limit exceeded", status: 429)
      else
        object.send("#{method}_without_rate_limit", *args)
      end
    end
  end

  # Persistence helpers
  def find_module_executions(module_name: nil, status: nil)
    repo = Desiru::Persistence::Repositories::ModuleExecutionRepository.new
    executions = repo.all
    
    executions = executions.select { |e| e.module_name == module_name } if module_name
    executions = executions.select { |e| e.status == status } if status
    
    executions
  end

  def find_job_results(job_type: nil, status: nil)
    repo = Desiru::Persistence::Repositories::JobResultRepository.new
    results = repo.all
    
    results = results.select { |r| r.job_type == job_type } if job_type
    results = results.select { |r| r.status == status } if status
    
    results
  end

  # Webhook helpers
  def stub_webhook(url, response: { status: 200, body: "OK" })
    stub_request(:post, url).to_return(response)
  end

  def stub_failing_webhook(url, times: 3)
    attempt = 0
    stub_request(:post, url).to_return do
      attempt += 1
      if attempt < times
        { status: 500, body: "Server Error" }
      else
        { status: 200, body: "OK" }
      end
    end
  end

  # Rate limiting helpers
  def with_rate_limiter(max_requests: 10, window: 1.second)
    limiter = Desiru::RateLimiter.new(
      max_requests: max_requests,
      window: window
    )
    
    Desiru.configure { |c| c.rate_limiter = limiter }
    yield limiter
  ensure
    Desiru.configure { |c| c.rate_limiter = nil }
  end

  # Circuit breaker helpers
  def with_circuit_breaker(failure_threshold: 3, reset_timeout: 1)
    breaker = Desiru::CircuitBreaker.new(
      failure_threshold: failure_threshold,
      reset_timeout: reset_timeout
    )
    yield breaker
  end

  def trip_circuit_breaker(breaker, error_class = StandardError)
    breaker.failure_threshold.times do
      breaker.call { raise error_class, "Tripping breaker" } rescue nil
    end
  end
end

# RSpec configuration
RSpec.configure do |config|
  config.include IntegrationHelpers, type: :integration
  
  config.before(:each, type: :integration) do
    setup_test_database if defined?(Desiru::Persistence::Database)
  end
  
  config.after(:each, type: :integration) do
    cleanup_test_database if defined?(Desiru::Persistence::Database)
  end
end