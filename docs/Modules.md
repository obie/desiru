# Modules

Modules are the core building blocks of Desiru programs. Each module encapsulates a specific pattern of interaction with language models. This guide covers all built-in modules and how to create custom ones.

## Module Overview

All Desiru modules inherit from `Desiru::Module` and implement:
- A signature defining inputs/outputs
- A `forward` method containing the logic
- Optional configuration parameters

```ruby
# Basic module usage
module = Desiru::Predict.new("question -> answer")
result = module.call(question: "What is Ruby?")
```

## Built-in Modules

### Predict

The simplest module - direct prediction without reasoning traces.

```ruby
# Basic usage
predict = Desiru::Predict.new("text -> summary")

# With configuration
predict = Desiru::Predict.new(
  "document: string, max_words: int -> summary: string",
  model: custom_model,
  temperature: 0.7
)

# Multiple outputs
classifier = Desiru::Predict.new(
  "text -> category, confidence: float"
)
```

**When to use**: 
- Simple transformations
- Classifications
- When reasoning trace isn't needed

### ChainOfThought

Generates step-by-step reasoning before the final answer.

```ruby
# Basic usage
cot = Desiru::ChainOfThought.new("problem -> solution")
result = cot.call(problem: "How do I reverse a string in Ruby?")

# Access reasoning
puts result.reasoning  # Step-by-step thought process
puts result.solution   # Final answer

# Custom reasoning field
math_solver = Desiru::ChainOfThought.new(
  "equation -> answer: float",
  reasoning_field: :work_shown
)
```

**When to use**:
- Complex problem solving
- Mathematical calculations
- When you need explainable outputs

### ReAct (Reasoning and Acting)

Enables agents that can use tools to gather information and solve problems.

```ruby
# Define tools
class SearchTool
  def self.name
    "web_search"
  end
  
  def self.description
    "Search the web for information. Args: query (string)"
  end
  
  def self.call(query:)
    # Your search implementation
    "Results for #{query}..."
  end
end

class Calculator
  def self.name
    "calculate"
  end
  
  def self.description
    "Perform calculations. Args: expression (string)"
  end
  
  def self.call(expression:)
    eval(expression).to_s
  rescue => e
    "Error: #{e.message}"
  end
end

# Create ReAct agent
agent = Desiru::Modules::ReAct.new(
  "question -> answer",
  tools: [SearchTool, Calculator],
  max_iterations: 5
)

# The agent will use tools as needed
result = agent.call(
  question: "What's the population of Tokyo times 2?"
)
# Agent will: 
# 1. Search for Tokyo's population
# 2. Use calculator to multiply by 2
# 3. Return the final answer
```

**Tool formats**:

```ruby
# Class format (shown above)

# Hash format
search_tool = {
  name: "search",
  description: "Search for information",
  call: ->(query:) { "Results: #{query}" }
}

# Callable format
calculator = ->(expression:) { eval(expression) }
```

**When to use**:
- Building agents that need external information
- Multi-step problems requiring different tools
- Interactive assistants

### Retrieve

For retrieval-augmented generation (RAG) systems.

```ruby
# Basic retrieval
retriever = Desiru::Retrieve.new(k: 5)

# With custom embedding model
retriever = Desiru::Retrieve.new(
  k: 10,
  embedding_model: custom_embedder,
  similarity_threshold: 0.7
)

# Use with vector store
results = retriever.call(
  "Ruby metaprogramming techniques",
  index: vector_store
)

# Results include relevance scores
results.each do |doc|
  puts "Document: #{doc.content}"
  puts "Score: #{doc.score}"
end
```

**Integration with RAG pipeline**:

```ruby
class RAGPipeline < Desiru::Program
  def initialize(vector_store)
    @retriever = Desiru::Retrieve.new(k: 3)
    @generator = Desiru::ChainOfThought.new(
      "context: list[string], question -> answer"
    )
    @vector_store = vector_store
  end
  
  def forward(question:)
    # Retrieve relevant documents
    docs = @retriever.call(question, index: @vector_store)
    
    # Generate answer using retrieved context
    @generator.call(
      context: docs.map(&:content),
      question: question
    )
  end
end
```

**When to use**:
- Question answering over documents
- Semantic search
- Any task requiring external knowledge

## Creating Custom Modules

### Basic Custom Module

```ruby
class SentimentAnalyzer < Desiru::Module
  def initialize(granularity: 5)
    super()
    @granularity = granularity
    @signature = Desiru::Signature.new(
      "text: string -> sentiment: float, confidence: float"
    )
  end
  
  def forward(text:)
    # Your custom logic here
    prompt = build_prompt(text)
    response = @model.complete(prompt: prompt)
    
    # Parse response and return structured output
    {
      sentiment: extract_sentiment(response),
      confidence: extract_confidence(response)
    }
  end
  
  private
  
  def build_prompt(text)
    "Analyze sentiment on a scale of 1-#{@granularity}: #{text}"
  end
end
```

### Module with State

```ruby
class StatefulSummarizer < Desiru::Module
  def initialize
    super()
    @signature = Desiru::Signature.new("text -> summary")
    @summary_history = []
  end
  
  def forward(text:)
    # Use history for context
    context = @summary_history.last(3).join("\n")
    
    prompt = "Previous summaries:\n#{context}\n\nSummarize: #{text}"
    summary = @model.complete(prompt: prompt)
    
    # Update state
    @summary_history << summary
    
    { summary: summary }
  end
  
  def reset_history
    @summary_history = []
  end
end
```

### Module with Multiple Models

```ruby
class MultiModelModule < Desiru::Module
  def initialize
    super()
    @fast_model = Desiru::Models::OpenAI.new(model: 'gpt-3.5-turbo')
    @smart_model = Desiru::Models::OpenAI.new(model: 'gpt-4')
    @signature = Desiru::Signature.new("query -> response")
  end
  
  def forward(query:)
    # Use fast model for classification
    complexity = assess_complexity(query)
    
    # Route to appropriate model
    model = complexity > 0.7 ? @smart_model : @fast_model
    
    response = model.complete(prompt: "Answer: #{query}")
    { response: response }
  end
end
```

### Async-Capable Module

```ruby
class AsyncProcessor < Desiru::Module
  include Desiru::AsyncCapable
  
  def initialize
    super()
    @signature = Desiru::Signature.new("data -> result")
  end
  
  def forward(data:)
    # Long-running process
    sleep 5 # Simulate work
    { result: "Processed #{data}" }
  end
end

# Use async
processor = AsyncProcessor.new
job = processor.call_async(data: "important info")
result = job.wait # Or check job.ready?
```

## Module Composition

### Sequential Composition

```ruby
class Pipeline < Desiru::Program
  def initialize
    @step1 = Desiru::Predict.new("input -> intermediate")
    @step2 = Desiru::ChainOfThought.new("intermediate -> output")
  end
  
  def forward(input:)
    intermediate = @step1.call(input: input)
    @step2.call(intermediate: intermediate.intermediate)
  end
end
```

### Parallel Composition

```ruby
class ParallelAnalyzer < Desiru::Program
  def initialize
    @sentiment = Desiru::Predict.new("text -> sentiment")
    @entities = Desiru::Predict.new("text -> entities: list[string]")
    @summary = Desiru::Predict.new("text -> summary")
  end
  
  def forward(text:)
    # Run in parallel (conceptually)
    results = {
      sentiment: @sentiment.call(text: text).sentiment,
      entities: @entities.call(text: text).entities,
      summary: @summary.call(text: text).summary
    }
  end
end
```

### Conditional Composition

```ruby
class ConditionalRouter < Desiru::Program
  def initialize
    @classifier = Desiru::Predict.new(
      "text -> type: Literal['technical', 'casual', 'formal']"
    )
    @technical = TechnicalProcessor.new
    @casual = CasualProcessor.new
    @formal = FormalProcessor.new
  end
  
  def forward(text:)
    text_type = @classifier.call(text: text).type
    
    case text_type
    when 'technical' then @technical.call(text: text)
    when 'casual' then @casual.call(text: text)
    when 'formal' then @formal.call(text: text)
    end
  end
end
```

## Module Configuration

### Model Configuration

```ruby
# Per-module model
module = Desiru::Predict.new(
  "question -> answer",
  model: Desiru::Models::Anthropic.new(
    model: 'claude-3-opus',
    temperature: 0.3
  )
)
```

### Retry Configuration

```ruby
module = Desiru::ChainOfThought.new(
  "question -> answer",
  max_retries: 3,
  retry_delay: 1.0
)
```

### Caching Configuration

```ruby
# Module-level cache
module = Desiru::Predict.new(
  "question -> answer",
  cache: Desiru::Cache::Redis.new(
    redis: Redis.new,
    ttl: 3600
  )
)
```

## Best Practices

1. **Choose the right module**: Use Predict for simple tasks, ChainOfThought for complex reasoning
2. **Compose small modules**: Build complex behavior from simple pieces
3. **Handle errors gracefully**: Implement proper error handling in custom modules
4. **Use appropriate models**: Match model capability to task complexity
5. **Cache when possible**: Reduce costs and latency with caching
6. **Test thoroughly**: Write tests for custom modules
7. **Document behavior**: Clearly document what your custom modules do

## Next Steps

- Learn about [Optimization](Optimizers-Overview) to improve module performance
- Explore [Testing Strategies](Testing-Strategies) for modules
- See [Tutorial: Custom Modules](Tutorial-Custom-Modules) for advanced examples
- Check the [API Reference](API-Module) for detailed documentation