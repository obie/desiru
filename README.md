# DeSIRu - Declarative Self-Improving Ruby

A Ruby implementation of [DSPy](https://dspy.ai/), the framework for programming—not prompting—language models. Build sophisticated AI systems with modular, composable code instead of brittle prompt strings.

Note: This project is in its earliest stages of development and experimental. Expect many bugs and breaking changes.


## Overview

Desiru brings the power of DSPy to the Ruby ecosystem, enabling developers to:
- Write declarative AI programs using Ruby's elegant syntax
- Automatically optimize prompts and few-shot examples
- Build portable AI systems that work across different language models
- Create maintainable, testable AI applications

Desiru leverages [Raix](https://github.com/OlympiaAI/raix) under the hood as its primary chat completion interface, providing seamless support for OpenAI and OpenRouter APIs with features like streaming, function calling, and prompt caching.

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
