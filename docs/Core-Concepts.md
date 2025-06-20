# Core Concepts

Understanding Desiru's core concepts is essential for building effective AI programs. This guide covers the fundamental building blocks: Signatures, Fields, Modules, and Programs.

## Overview

Desiru follows a declarative approach where you describe **what** you want your AI to do, not **how** to prompt for it. The framework handles prompt generation, optimization, and execution.

```ruby
# Instead of crafting prompts...
prompt = "Given the question '#{question}', provide a detailed answer."

# You declare intentions
qa = Desiru::Predict.new("question -> answer")
```

## Signatures

Signatures define the input/output contract for your AI components. They're the foundation of Desiru's declarative approach.

### Basic Signatures

```ruby
# Simple signature with one input and output
"question -> answer"

# Multiple inputs
"context, question -> answer"

# Multiple outputs
"text -> summary, keywords"
```

### Typed Signatures

Add type annotations for better control:

```ruby
# Basic types
"text: string, max_length: int -> summary: string"

# Lists
"documents: list[string] -> summary: string"

# Literal types (enums)
"text -> sentiment: Literal['positive', 'negative', 'neutral']"

# Optional fields
"text, language: string? -> translation"
```

### Descriptions

Provide descriptions to guide the model:

```ruby
sig = Desiru::Signature.new(
  "document: string, style: string -> summary: string",
  descriptions: {
    document: "The text document to summarize",
    style: "Writing style: 'technical', 'casual', or 'executive'",
    summary: "A concise summary in the specified style"
  }
)
```

## Fields

Fields represent individual inputs or outputs in a signature.

```ruby
# Create fields explicitly
question_field = Desiru::Field.new(
  name: :question,
  type: String,
  description: "The question to answer"
)

answer_field = Desiru::Field.new(
  name: :answer,
  type: String,
  description: "The comprehensive answer",
  optional: false
)

# Fields are usually created automatically from signatures
sig = Desiru::Signature.parse("question -> answer")
sig.input_fields  # => [Field(name: :question)]
sig.output_fields # => [Field(name: :answer)]
```

### Field Types

Supported field types:

- `String` - Text data
- `Integer` - Whole numbers
- `Float` - Decimal numbers
- `Boolean` - True/false values
- `Array` - Lists (e.g., `list[string]`)
- `Literal` - Enumerated values

## Modules

Modules are the building blocks of Desiru programs. They encapsulate specific AI capabilities.

### Built-in Modules

#### Predict
Basic prediction without reasoning traces:

```ruby
predict = Desiru::Predict.new("question -> answer")
result = predict.call(question: "What is Ruby?")
```

#### ChainOfThought
Includes step-by-step reasoning:

```ruby
cot = Desiru::ChainOfThought.new("problem -> solution")
result = cot.call(problem: "How do I sort an array in Ruby?")
puts result.reasoning # Shows thought process
puts result.solution  # Final answer
```

#### ReAct
For tool-using agents:

```ruby
tools = [SearchTool, CalculatorTool]
agent = Desiru::ReAct.new("question -> answer", tools: tools)
```

#### Retrieve
For retrieval-augmented generation:

```ruby
retriever = Desiru::Retrieve.new(k: 5)
docs = retriever.call("Ruby metaprogramming", index: vector_store)
```

### Custom Modules

Create your own modules by inheriting from `Desiru::Module`:

```ruby
class Translator < Desiru::Module
  def initialize(target_language)
    super()
    @target_language = target_language
    @signature = Desiru::Signature.new("text -> translation")
  end
  
  def forward(text:)
    # Custom logic here
    prompt = "Translate to #{@target_language}: #{text}"
    result = @model.complete(prompt: prompt)
    
    { translation: result }
  end
end

# Use your custom module
translator = Translator.new("Spanish")
result = translator.call(text: "Hello, world!")
```

## Programs

Programs combine multiple modules into complex pipelines.

### Basic Program Structure

```ruby
class AnalysisPipeline < Desiru::Program
  def initialize
    @extractor = Desiru::Predict.new("text -> key_points: list[string]")
    @analyzer = Desiru::ChainOfThought.new("key_points -> analysis")
    @summarizer = Desiru::Predict.new("analysis -> summary")
  end
  
  def forward(text:)
    # Extract key points
    points = @extractor.call(text: text)
    
    # Analyze them
    analysis = @analyzer.call(key_points: points.key_points)
    
    # Generate summary
    @summarizer.call(analysis: analysis.analysis)
  end
end
```

### Program Composition

Programs can include other programs:

```ruby
class MetaAnalyzer < Desiru::Program
  def initialize
    @pipeline1 = AnalysisPipeline.new
    @pipeline2 = AnotherPipeline.new
    @combiner = Desiru::Predict.new("results: list -> final_analysis")
  end
  
  def forward(text:)
    result1 = @pipeline1.call(text: text)
    result2 = @pipeline2.call(text: text)
    
    @combiner.call(results: [result1, result2])
  end
end
```

## Models and Adapters

Desiru uses adapters to work with different LLMs:

```ruby
# Configure globally
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY']
  )
end

# Or per-module
gpt4_module = Desiru::Predict.new(
  "question -> answer",
  model: Desiru::Models::OpenAI.new(model: 'gpt-4')
)

claude_module = Desiru::Predict.new(
  "question -> answer", 
  model: Desiru::Models::Anthropic.new(model: 'claude-3-opus')
)
```

## Optimization

Desiru can automatically optimize your programs:

```ruby
# Create training data
trainset = [
  { text: "Ruby is great", sentiment: "positive" },
  { text: "This is broken", sentiment: "negative" }
]

# Basic module
classifier = Desiru::Predict.new(
  "text -> sentiment: Literal['positive', 'negative']"
)

# Optimize with examples
optimizer = Desiru::BootstrapFewShot.new(metric: :exact_match)
optimized = optimizer.compile(classifier, trainset: trainset)

# The optimized module includes selected examples in prompts
```

## Caching

Desiru includes built-in caching to reduce API calls:

```ruby
# Configure caching
Desiru.configure do |config|
  config.cache_store = Desiru::Cache::Memory.new(
    max_size: 100,
    ttl: 3600 # 1 hour
  )
end

# Caching happens automatically for identical inputs
qa = Desiru::Predict.new("question -> answer")
qa.call(question: "What is 2+2?") # Calls API
qa.call(question: "What is 2+2?") # Returns cached result
```

## Error Handling

Desiru provides consistent error handling:

```ruby
begin
  result = module.call(input: value)
rescue Desiru::ModelError => e
  # Handle model/API errors
  puts "Model error: #{e.message}"
rescue Desiru::ValidationError => e
  # Handle validation errors
  puts "Invalid input: #{e.message}"
rescue Desiru::TimeoutError => e
  # Handle timeouts
  puts "Request timed out"
end
```

## Best Practices

1. **Start with simple signatures** and add complexity as needed
2. **Use type annotations** for better reliability
3. **Provide descriptions** for complex fields
4. **Compose small modules** into larger programs
5. **Cache expensive operations** to reduce costs
6. **Handle errors gracefully** in production
7. **Test with examples** before optimization

## Next Steps

- Explore [Built-in Modules](Modules) in detail
- Learn about [Testing Strategies](Testing-Strategies)
- Understand [Optimization](Optimizers-Overview) techniques
- Build your first [RAG Pipeline](Tutorial-RAG-Pipeline)