# DeSIRu - Declarative Self-Improving Ruby

A Ruby implementation of [DSPy](https://dspy.ai/), the framework for programming—not prompting—language models. Build sophisticated AI systems with modular, composable code instead of brittle prompt strings.

**Note: This project was an experiment that will not be developed further. For an active implementation of the same concept see [DSPY.rb](https://oss.vicente.services/dspy.rb/)**


## Overview

Desiru brings the power of DSPy to the Ruby ecosystem, enabling developers to:
- Write declarative AI programs using Ruby's elegant syntax
- Automatically optimize prompts and few-shot examples
- Build portable AI systems that work across different language models
- Create maintainable, testable AI applications

Desiru provides direct integrations with multiple language model providers including OpenAI, Anthropic, and OpenRouter, with features like streaming, function calling, and prompt caching.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'desiru'
```

And then execute:

```bash
$ bundle install
```

Or install it yourself as:

```bash
$ gem install desiru
```

## Quick Start

```ruby
require 'desiru'

# Configure your language model
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(api_key: ENV['OPENAI_API_KEY'])
end

# Define a simple question-answering signature
math = Desiru::ChainOfThought.new("question -> answer: float")

# Use it!
result = math.call(question: "Two dice are tossed. What is the probability that the sum equals two?")
puts result.answer # => 0.0278
```

## Core Concepts

### Signatures

Signatures define the input/output behavior of your AI components:

```ruby
# Simple signature
qa = Desiru::Signature.new("question -> answer")

# Typed signature with descriptions
summarizer = Desiru::Signature.new(
  "document: string, max_length: int -> summary: string",
  descriptions: {
    document: "The text to summarize",
    max_length: "Maximum number of words in summary",
    summary: "A concise summary of the document"
  }
)
```

### Modules

Desiru provides several built-in modules for different reasoning patterns:

```ruby
# Basic prediction
predict = Desiru::Predict.new("question -> answer")

# Chain of Thought reasoning
cot = Desiru::ChainOfThought.new("question -> answer")

# ReAct pattern for tool use
react = Desiru::ReAct.new("question -> answer", tools: [calculator, search])

# Program of Thought - generates and executes code
pot = Desiru::ProgramOfThought.new("problem -> solution: float")

# Best of N - samples multiple outputs and selects the best
best_of_n = Desiru::BestOfN.new("question -> answer", n_samples: 3, selection_criterion: :consistency)

# Compose modules into programs
class RAGPipeline < Desiru::Program
  def initialize
    @retrieve = Desiru::Retrieve.new(k: 3)
    @generate = Desiru::ChainOfThought.new("context, question -> answer")
  end

  def forward(question)
    context = @retrieve.call(question)
    @generate.call(context: context, question: question)
  end
end
```

### Optimizers

Automatically improve your AI programs:

```ruby
# Create a simple training set
trainset = [
  { question: "What is 2+2?", answer: "4" },
  { question: "What is the capital of France?", answer: "Paris" }
]

# Optimize with few-shot examples
optimizer = Desiru::BootstrapFewShot.new(metric: :exact_match)
optimized_program = optimizer.compile(program, trainset: trainset)

# Or use more advanced optimization
optimizer = Desiru::MIPROv2.new(
  metric: :f1,
  num_candidates: 10,
  max_bootstrapped_demos: 3
)
```

## Advanced Usage

### Custom Metrics

```ruby
def relevance_metric(prediction, ground_truth)
  # Your custom evaluation logic
  score = calculate_similarity(prediction.answer, ground_truth.answer)
  score > 0.8 ? 1.0 : 0.0
end

optimizer = Desiru::BootstrapFewShot.new(metric: method(:relevance_metric))
```

### Multi-Stage Pipelines

```ruby
class AdvancedQA < Desiru::Program
  def initialize
    @understand = Desiru::ChainOfThought.new("question -> interpretation")
    @decompose = Desiru::Predict.new("question -> subquestions: list[str]")
    @answer_sub = Desiru::ChainOfThought.new("subquestion -> subanswer")
    @synthesize = Desiru::ChainOfThought.new("subresults -> final_answer")
  end

  def forward(question)
    interpretation = @understand.call(question: question)
    subquestions = @decompose.call(question: question)
    
    subresults = subquestions.subquestions.map do |subq|
      @answer_sub.call(subquestion: subq)
    end
    
    @synthesize.call(subresults: subresults)
  end
end
```

### Model Adapters

Desiru supports multiple language model providers:

```ruby
# OpenAI
model = Desiru::Models::OpenAI.new(
  api_key: ENV['OPENAI_API_KEY'],
  model: 'gpt-4-turbo-preview'
)

# Anthropic
model = Desiru::Models::Anthropic.new(
  api_key: ENV['ANTHROPIC_API_KEY'],
  model: 'claude-3-opus-20240229'
)

# Local models via Ollama
model = Desiru::Models::Ollama.new(
  model: 'llama2:70b',
  base_url: 'http://localhost:11434'
)

# Use with any module
cot = Desiru::ChainOfThought.new("question -> answer", model: model)
```

### Assertions and Validation

Desiru provides an assertions system for validating module outputs and enforcing constraints:

```ruby
# Configure assertions
Desiru::Assertions.configure do |config|
  config.max_assertion_retries = 3    # Retry failed assertions up to 3 times
  config.assertion_retry_delay = 0.5  # Wait 0.5s between retries
end

# Use assertions in your modules
class FactChecker < Desiru::Module
  def forward(statement:)
    result = @model.complete(prompt: "Verify: #{statement}")
    confidence = extract_confidence(result)
    
    # Hard assertion - will retry if confidence is too low
    Desiru.assert(confidence > 0.8, "Confidence too low: #{confidence}")
    
    { statement: statement, confidence: confidence, verified: true }
  end
end

# Use suggestions for soft constraints
class CodeReviewer < Desiru::Module
  def forward(code:)
    review = analyze_code(code)
    
    # Soft suggestion - logs warning but continues
    Desiru.suggest(review[:test_coverage] > 0.7, "Test coverage below 70%")
    Desiru.suggest(review[:complexity] < 10, "Code complexity too high")
    
    review
  end
end
```

Key features:
- **Assertions** (`Desiru.assert`) - Enforce hard constraints with automatic retries
- **Suggestions** (`Desiru.suggest`) - Log warnings for soft constraints
- **Configurable retries** - Control retry behavior for failed assertions
- **Module integration** - Assertions are fully integrated with the module retry system

See `examples/assertions_example.rb` for more detailed examples.

### REST API with Grape

Desiru provides Grape integration for building REST APIs:

```ruby
require 'desiru/api'

# Create API with your modules
api = Desiru::API::GrapeIntegration.new
api.register_module('/qa', qa_module, description: 'Question answering')
api.register_module('/summarize', summarizer, description: 'Text summarization')

# Mount as Rack app
run api.to_rack_app
```

Features:
- **Automatic endpoint generation** from Desiru signatures
- **Parameter validation** based on signature types
- **CORS support** built-in
- **Async support** (when enabled in modules)
- **Streaming endpoints** for real-time responses

Example endpoints:
```bash
# Synchronous request
curl -X POST http://localhost:9292/api/v1/qa \
  -H "Content-Type: application/json" \
  -d '{"question": "What is Ruby?"}'

# Async request
curl -X POST http://localhost:9292/api/v1/summarize \
  -H "Content-Type: application/json" \
  -d '{"text": "Long text...", "max_words": 100, "async": true}'

# Check job status
curl http://localhost:9292/api/v1/jobs/JOB_ID

# Check API health
curl http://localhost:9292/api/v1/health
```

See `examples/rest_api.rb` and `examples/rest_api_advanced.rb` for complete examples.

### REST API with Sinatra

Desiru also supports Sinatra for lightweight REST APIs:

```ruby
require 'desiru/api'

# Create API with Sinatra (lightweight alternative to Grape)
api = Desiru::API.sinatra do
  register_module '/qa', qa_module, description: 'Question answering'
  register_module '/summarize', summarizer, description: 'Text summarization'
end

# Or explicitly specify the framework
api = Desiru::API.create(framework: :sinatra) do
  register_module '/process', processor
end

# Mount as Rack app
run api.to_rack_app
```

Features:
- **Lightweight** - Minimal dependencies with Sinatra
- **Same interface** as Grape integration
- **Full compatibility** with all Desiru module features
- **CORS support** built-in
- **Async support** for background processing
- **Streaming endpoints** for real-time responses

See `examples/sinatra_api.rb` for a complete example.

### Background Processing

Desiru includes built-in support for asynchronous processing using Sidekiq:

```ruby
# Configure Redis for background jobs
Desiru.configure do |config|
  config.redis_url = 'redis://localhost:6379'
end

# Single async prediction
module = Desiru::Predict.new("question -> answer")
result = module.call_async(question: "What is 2+2?")

# Check status and progress
result.ready? # => false (still processing)
result.status # => "running", "completed", "failed", etc.
result.progress # => 0-100 (percentage complete)
result.success? # => true/false (when ready)

# Wait for result
answer = result.wait(timeout: 30) # Blocks until ready
puts answer.result # => "4"

# Batch processing
questions = [
  { question: "What is 2+2?" },
  { question: "What is 3+3?" }
]
batch_result = module.call_batch_async(questions)

# Get batch statistics
batch_result.wait
stats = batch_result.stats
# => { total: 2, successful: 2, failed: 0, success_rate: 1.0 }

# Background optimization
optimizer = Desiru::BootstrapFewShot.new(metric: :f1)
job_id = optimizer.compile_async(program, trainset: examples)
```

To use background processing:
1. Add `redis` to your Gemfile
2. Run Sidekiq workers: `bundle exec sidekiq`
3. Use `call_async` methods on modules

### Background Processing: DSPy vs Desiru

While DSPy (Python) includes async support through Python's `asyncio`, Desiru takes a different approach using Sidekiq and Redis. This design choice reflects the different ecosystems and typical deployment patterns:

#### DSPy's Async Approach
- **In-process concurrency** using Python's `asyncio`
- Runs multiple LLM calls concurrently within the same process
- No persistence - results are lost if the process crashes
- Best suited for scripts, notebooks, and research

```python
# DSPy async example
async def main():
    output = await predict.acall(question="What is 2+2?")
```

#### Desiru's Background Jobs Approach
- **True background processing** with separate worker processes
- Jobs persist in Redis and survive application restarts
- Built for production web applications (Rails, Sinatra, etc.)
- Includes job prioritization, retries, and monitoring

| Feature | DSPy (asyncio) | Desiru (Sidekiq/Redis) |
|---------|----------------|------------------------|
| **Architecture** | Single process | Distributed workers |
| **Persistence** | None | Redis with configurable TTL |
| **Failure handling** | Basic exceptions | Retries, dead letter queues |
| **Monitoring** | None | Sidekiq Web UI |
| **Use case** | Research, notebooks | Production web apps |

This approach makes Desiru particularly well-suited for:
- Web applications that need non-blocking LLM operations
- Batch processing of large datasets
- Systems requiring job persistence and reliability
- Deployments that need to scale horizontally

### Database Persistence with Sequel

Desiru includes a comprehensive persistence layer using Sequel for tracking:
- Module execution history and performance metrics
- API request/response data for analytics
- Training examples and optimization results
- Model performance over time

```ruby
# Configure persistence
require 'desiru/persistence'

Desiru::Persistence.database_url = 'postgres://localhost/desiru'
Desiru::Persistence.connect!
Desiru::Persistence.migrate!

# Track module executions
execution = Desiru::Persistence[:module_executions].create_for_module(
  'TextSummarizer',
  { text: 'Long article...' }
)

# Complete with results
Desiru::Persistence[:module_executions].complete(
  execution.id,
  { summary: 'Short summary' },
  { model: 'gpt-3.5-turbo', tokens: 150 }
)

# Query performance metrics
repo = Desiru::Persistence[:module_executions]
puts "Success rate: #{repo.success_rate('TextSummarizer')}%"
puts "Average duration: #{repo.average_duration('TextSummarizer')}s"

# Store training examples
examples = [
  { inputs: { text: 'Example 1' }, outputs: { summary: 'Summary 1' } },
  { inputs: { text: 'Example 2' }, outputs: { summary: 'Summary 2' } }
]

Desiru::Persistence[:training_examples].bulk_create('TextSummarizer', examples)

# Export for training
data = Desiru::Persistence[:training_examples].export_for_training(
  'TextSummarizer',
  format: :dspy
)
```

#### API Request Tracking

Automatically track all API requests with the persistence middleware:

```ruby
# Add persistence to your API
api = Desiru::API.create do
  register_module '/summarize', summarizer
end

# Enable automatic request tracking
app = api.with_persistence(enabled: true)

# Query API metrics
requests = Desiru::Persistence[:api_requests]
puts "Requests per minute: #{requests.requests_per_minute}"
puts "Average response time: #{requests.average_response_time}s"
puts "Top endpoints: #{requests.top_paths(5)}"
```

Features:
- **Automatic tracking** of all API requests and module executions
- **Performance analytics** including success rates and response times
- **Training data management** with dataset splitting and export
- **Optimization tracking** to measure improvements over time
- **Multiple database support** via Sequel (PostgreSQL, MySQL, SQLite)

### ReAct Module (Tool-Using Agents)

The ReAct module enables building AI agents that can reason about tasks and use tools to gather information:

```ruby
# Define tools for your agent
class WeatherTool
  def self.name
    "get_weather"
  end
  
  def self.description
    "Get current weather for a city. Args: city (string)"
  end
  
  def self.call(city:)
    # Your weather API integration
    "Current weather in #{city}: sunny, 72°F"
  end
end

# Create a ReAct agent with tools
tools = [WeatherTool, CalculatorTool]
agent = Desiru::Modules::ReAct.new(
  'question: string -> answer: string',
  tools: tools,
  max_iterations: 5
)

# The agent will reason and use tools to answer
result = agent.call(
  question: "What's the weather in Tokyo and is 72°F warm in Celsius?"
)
# The agent will:
# 1. Call get_weather tool for Tokyo
# 2. Use calculator to convert 72°F to Celsius
# 3. Synthesize the final answer
```

Key features:
- **Flexible tool format**: Pass tools as classes, hashes, or callables
- **Automatic reasoning**: The agent decides which tools to use and when
- **Trajectory management**: Automatically handles long conversations
- **Error handling**: Gracefully handles tool execution failures
- **Iteration limits**: Prevents infinite loops

### GraphQL Integration

Desiru provides GraphQL integration with automatic schema generation and efficient batch loading:

```ruby
require 'desiru/graphql'

# Register your Desiru modules
generator = Desiru::GraphQL::SchemaGenerator.new
generator.register_signature('questionAnswer', qa_module)
generator.register_signature('summarize', summarizer_module)

# Generate GraphQL schema
schema = generator.generate_schema

# Use with your GraphQL server
result = schema.execute(
  query,
  context: { current_user: user },
  variables: variables
)
```

Features include:
- **Automatic schema generation** from Desiru signatures
- **DataLoader pattern** for N+1 query prevention
- **Batch execution** for multiple queries
- **Type mapping** including support for Literal types as GraphQL enums
- **Thread-safe** promise-based lazy loading

#### GraphQL Batch Loading Example

```ruby
# The executor automatically batches multiple field requests
executor = Desiru::GraphQL::Executor.new(schema)

# Execute multiple queries efficiently in a single batch
results = executor.execute_batch([
  { query: query1, variables: vars1 },
  { query: query2, variables: vars2 }
])
```


## Examples

### Retrieval-Augmented Generation (RAG)

```ruby
class SimpleRAG < Desiru::Program
  def initialize(vectorstore)
    @vectorstore = vectorstore
    @retrieve = Desiru::Retrieve.new(k: 5)
    @generate = Desiru::ChainOfThought.new(
      "context: list[str], question: str -> answer: str"
    )
  end

  def forward(question)
    docs = @retrieve.call(question, index: @vectorstore)
    @generate.call(context: docs, question: question)
  end
end

# Usage
rag = SimpleRAG.new(my_vectorstore)
result = rag.call("What are the main features of Ruby 3.0?")
```

### Classification with Reasoning

```ruby
classifier = Desiru::ChainOfThought.new(
  "text -> sentiment: Literal['positive', 'negative', 'neutral']"
)

# Optimize with examples
optimizer = Desiru::BootstrapFewShot.new(max_labeled_demos: 8)
classifier = optimizer.compile(classifier, trainset: sentiment_examples)

# Use it
result = classifier.call(text: "This framework is amazing!")
puts result.sentiment # => "positive"
puts result.reasoning # => "The text uses positive language..."
```

## Testing

Desiru programs are testable Ruby code:

```ruby
RSpec.describe MyRAGPipeline do
  let(:pipeline) { described_class.new }
  
  it "retrieves relevant documents" do
    result = pipeline.call("What is Ruby?")
    expect(result.answer).to include("programming language")
  end
  
  it "handles complex questions" do
    # Test with mocked models for deterministic results
    allow(pipeline).to receive(:model).and_return(mock_model)
    # ...
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/obie/desiru.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgments

Desiru is a Ruby port of [DSPy](https://github.com/stanfordnlp/dspy) by Stanford NLP. Special thanks to the DSPy team for creating this innovative approach to language model programming.
