# API Reference: Desiru::Module

The base class for all Desiru modules. Provides core functionality for building AI components.

## Class: Desiru::Module

```ruby
class Desiru::Module
  include Desiru::AsyncCapable
  include Desiru::Cacheable
end
```

### Constructor

```ruby
new(**options) → Module
```

Creates a new module instance.

**Parameters:**
- `model:` (Model) - LLM model to use (defaults to configured default)
- `temperature:` (Float) - Temperature for generation (0.0-2.0)
- `max_retries:` (Integer) - Maximum retry attempts on failure
- `retry_delay:` (Float) - Delay between retries in seconds
- `cache:` (Cache) - Cache store for results
- `cache_key:` (Proc) - Custom cache key generator

**Example:**
```ruby
module = Desiru::Module.new(
  model: Desiru::Models::OpenAI.new(model: 'gpt-4'),
  temperature: 0.7,
  max_retries: 3
)
```

### Instance Methods

#### #call

```ruby
call(**inputs) → Hash
```

Execute the module with given inputs. This is the primary interface for using modules.

**Parameters:**
- `**inputs` - Keyword arguments matching the module's signature inputs

**Returns:**
- Hash with keys matching the module's signature outputs

**Example:**
```ruby
result = module.call(question: "What is Ruby?")
puts result[:answer]
```

#### #forward

```ruby
forward(**inputs) → Hash
```

**Abstract method** - Must be implemented by subclasses. Contains the core logic of the module.

**Parameters:**
- `**inputs` - Keyword arguments from the signature

**Returns:**
- Hash with output fields

**Example:**
```ruby
class MyModule < Desiru::Module
  def forward(text:)
    # Process the text
    result = process(text)
    { summary: result }
  end
end
```

#### #signature

```ruby
signature → Signature
```

Returns the module's signature defining inputs and outputs.

**Example:**
```ruby
module.signature.input_fields  # => [Field(name: :question)]
module.signature.output_fields # => [Field(name: :answer)]
```

#### #compile

```ruby
compile(optimizer:, trainset:, **options) → Module
```

Optimize the module using the specified optimizer.

**Parameters:**
- `optimizer:` (Optimizer) - The optimizer to use
- `trainset:` (Array<Hash>) - Training examples
- `**options` - Additional optimizer options

**Returns:**
- New optimized module instance

**Example:**
```ruby
optimizer = Desiru::BootstrapFewShot.new(metric: :exact_match)
optimized = module.compile(optimizer: optimizer, trainset: examples)
```

#### #reset

```ruby
reset → self
```

Reset the module to its initial state, clearing any accumulated context or cache.

**Example:**
```ruby
module.reset
```

### Async Methods (via AsyncCapable)

#### #call_async

```ruby
call_async(**inputs) → AsyncResult
```

Execute the module asynchronously using background jobs.

**Parameters:**
- Same as `#call`

**Returns:**
- AsyncResult object for tracking job status

**Example:**
```ruby
result = module.call_async(question: "Complex question")
result.wait # Block until complete
puts result.value[:answer]
```

#### #call_batch_async

```ruby
call_batch_async(inputs_array) → BatchResult
```

Process multiple inputs asynchronously in batch.

**Parameters:**
- `inputs_array` (Array<Hash>) - Array of input hashes

**Returns:**
- BatchResult object for tracking batch progress

**Example:**
```ruby
questions = [
  { question: "What is Ruby?" },
  { question: "What is Python?" }
]
batch = module.call_batch_async(questions)
batch.wait
puts batch.stats # => { total: 2, successful: 2, failed: 0 }
```

### Caching Methods (via Cacheable)

#### #with_cache

```ruby
with_cache(cache: nil) { block } → result
```

Execute block with caching enabled.

**Parameters:**
- `cache:` (Cache) - Optional cache store (uses module's default if nil)
- `block` - Block to execute with caching

**Example:**
```ruby
result = module.with_cache do
  module.call(question: "What is 2+2?")
end
```

#### #clear_cache

```ruby
clear_cache → self
```

Clear all cached results for this module.

**Example:**
```ruby
module.clear_cache
```

### Class Methods

#### .signature

```ruby
signature(signature_string) → nil
```

Class-level DSL for defining module signature.

**Parameters:**
- `signature_string` (String) - Signature in DSPy format

**Example:**
```ruby
class QAModule < Desiru::Module
  signature "question: string -> answer: string"
  
  def forward(question:)
    # Implementation
  end
end
```

#### .model

```ruby
model(model_name) → nil
```

Set default model for all instances of this module class.

**Parameters:**
- `model_name` (Symbol, Model) - Model identifier or instance

**Example:**
```ruby
class SmartModule < Desiru::Module
  model :gpt4
end
```

## Hooks and Callbacks

### #before_call

```ruby
before_call(inputs) → Hash
```

Hook called before module execution. Can modify inputs.

**Parameters:**
- `inputs` (Hash) - The input hash

**Returns:**
- Modified inputs hash

**Example:**
```ruby
class ValidatingModule < Desiru::Module
  def before_call(inputs)
    raise ArgumentError, "Question too short" if inputs[:question].length < 5
    inputs
  end
end
```

### #after_call

```ruby
after_call(outputs) → Hash
```

Hook called after module execution. Can modify outputs.

**Parameters:**
- `outputs` (Hash) - The output hash

**Returns:**
- Modified outputs hash

**Example:**
```ruby
class PostProcessingModule < Desiru::Module
  def after_call(outputs)
    outputs[:answer] = outputs[:answer].strip.capitalize
    outputs[:timestamp] = Time.now
    outputs
  end
end
```

### #on_error

```ruby
on_error(error, inputs) → Hash or nil
```

Hook called when an error occurs during execution.

**Parameters:**
- `error` (Exception) - The error that occurred
- `inputs` (Hash) - The inputs that caused the error

**Returns:**
- Hash to use as fallback result, or nil to re-raise

**Example:**
```ruby
class ResilientModule < Desiru::Module
  def on_error(error, inputs)
    if error.is_a?(Desiru::ModelError)
      { answer: "I'm having trouble right now. Please try again.", error: true }
    else
      nil # Re-raise
    end
  end
end
```

## Error Handling

### Exceptions

- `Desiru::ModuleError` - Base error for module-related issues
- `Desiru::SignatureError` - Invalid signature or inputs
- `Desiru::ModelError` - LLM API errors
- `Desiru::TimeoutError` - Execution timeout
- `Desiru::ValidationError` - Input/output validation failure

**Example:**
```ruby
begin
  result = module.call(question: "test")
rescue Desiru::ModelError => e
  puts "Model error: #{e.message}"
  # Fallback logic
rescue Desiru::ValidationError => e
  puts "Invalid input: #{e.message}"
  # Handle validation
end
```

## Configuration

### Module-Level Configuration

```ruby
class ConfiguredModule < Desiru::Module
  configure do |config|
    config.default_temperature = 0.7
    config.max_retries = 5
    config.cache_ttl = 3600
  end
end
```

### Instance Configuration

```ruby
module = MyModule.new
module.configure do |config|
  config.model = custom_model
  config.temperature = 0.3
end
```

## Thread Safety

Modules are designed to be thread-safe for read operations. For write operations or stateful modules, synchronization may be needed:

```ruby
class ThreadSafeModule < Desiru::Module
  def initialize
    super
    @mutex = Mutex.new
    @counter = 0
  end
  
  def forward(input:)
    @mutex.synchronize do
      @counter += 1
      # Thread-safe operation
    end
    { count: @counter, result: process(input) }
  end
end
```

## Performance Considerations

1. **Caching**: Enable caching for expensive operations
2. **Batch Processing**: Use `call_batch_async` for multiple inputs
3. **Model Selection**: Use appropriate model size for task complexity
4. **Connection Pooling**: Models handle connection pooling automatically

## Integration with Desiru Ecosystem

### With Optimizers

```ruby
module = MyModule.new
optimizer = Desiru::BootstrapFewShot.new
optimized = optimizer.compile(module, trainset: data)
```

### With Persistence

```ruby
class TrackedModule < Desiru::Module
  def after_call(outputs)
    Desiru::Persistence[:module_executions].create_for_module(
      self.class.name,
      @last_inputs,
      outputs
    )
    outputs
  end
end
```

### With Programs

```ruby
class Pipeline < Desiru::Program
  def initialize
    @step1 = ModuleA.new
    @step2 = ModuleB.new
  end
  
  def forward(input:)
    result1 = @step1.call(input: input)
    @step2.call(data: result1[:output])
  end
end
```

## See Also

- [Predict Module](API-Module-Predict)
- [ChainOfThought Module](API-Module-ChainOfThought)
- [ReAct Module](API-Module-ReAct)
- [Custom Modules Tutorial](Tutorial-Custom-Modules)
- [Testing Modules](Testing-Strategies)