# Ruby Idioms for Desiru

This guide helps Python DSPy users understand Ruby patterns and idioms used in Desiru. Ruby's expressive syntax and powerful metaprogramming features enable elegant DSPy implementations.

## Key Ruby Concepts for Desiru

### Symbols vs Strings

Ruby uses symbols (`:name`) for identifiers and hash keys:

```ruby
# Python DSPy
result = predictor(question="What is Ruby?")
print(result.answer)

# Ruby Desiru
result = predictor.call(question: "What is Ruby?")
puts result.answer  # or result[:answer]
```

### Method Naming Conventions

Ruby follows specific naming patterns:

```ruby
# Predicates end with ?
module.ready?        # Instead of is_ready
result.valid?        # Instead of is_valid

# Dangerous methods end with !
module.compile!      # Modifies in place
cache.clear!         # Destructive operation

# Getters don't use 'get_'
module.signature     # Instead of get_signature
result.answer        # Instead of get_answer
```

### Blocks and Iterators

Ruby's blocks are powerful for configuration and iteration:

```ruby
# Configuration blocks
Desiru.configure do |config|
  config.default_model = model
  config.cache_enabled = true
end

# Iteration with blocks
results.each do |result|
  puts result.answer
end

# Select/filter with blocks
valid_results = results.select { |r| r.confidence > 0.8 }
```

### Hash Syntax

Modern Ruby hash syntax is cleaner:

```ruby
# Old syntax (still valid)
{ :question => "What is Ruby?", :temperature => 0.7 }

# Modern syntax (preferred)
{ question: "What is Ruby?", temperature: 0.7 }

# Mixed when using string keys
{ "api_key" => ENV['API_KEY'], model: 'gpt-4' }
```

## Common Patterns

### Module Definition

```ruby
# Python DSPy
class QAModule(dspy.Module):
    def __init__(self):
        super().__init__()
        self.predictor = dspy.Predict("question -> answer")
    
    def forward(self, question):
        return self.predictor(question=question)

# Ruby Desiru
class QAModule < Desiru::Module
  def initialize
    super
    @predictor = Desiru::Predict.new("question -> answer")
  end
  
  def forward(question:)
    @predictor.call(question: question)
  end
end
```

### Keyword Arguments

Ruby uses keyword arguments extensively:

```ruby
# Python DSPy
optimizer.compile(program, trainset=examples, metric=my_metric)

# Ruby Desiru
optimizer.compile(program, trainset: examples, metric: my_metric)

# With defaults
def compile(program, trainset:, metric: :exact_match, max_examples: 10)
  # ...
end
```

### Splat Operators

Ruby's splat operators handle variable arguments:

```ruby
# Array splat
tools = [SearchTool, Calculator]
agent = Desiru::ReAct.new("question -> answer", tools: tools)
# Or spread them
agent = Desiru::ReAct.new("question -> answer", tools: [*tools, EmailTool])

# Keyword splat
options = { temperature: 0.7, max_tokens: 100 }
model = Desiru::Models::OpenAI.new(api_key: key, **options)
```

### Duck Typing

Ruby embraces duck typing - objects are defined by their behavior:

```ruby
# Any object that responds to #call can be a tool
class SearchTool
  def self.call(query:)
    # Implementation
  end
end

# Lambda/Proc works too
calculator = ->(expression:) { eval(expression) }

# Both work with ReAct
agent = Desiru::ReAct.new("q -> a", tools: [SearchTool, calculator])
```

## Ruby-Specific Features

### Method Missing and Dynamic Methods

```ruby
# Access result fields dynamically
result = module.call(question: "What is Ruby?")
result.answer       # Same as result[:answer]
result.confidence   # Same as result[:confidence]

# This is implemented via method_missing
class Result
  def method_missing(method, *args)
    if @data.key?(method)
      @data[method]
    else
      super
    end
  end
end
```

### Module Inclusion

Ruby modules (mixins) add behavior:

```ruby
class MyModule < Desiru::Module
  include Desiru::AsyncCapable  # Adds async methods
  include Desiru::Cacheable      # Adds caching
  
  def forward(input:)
    # Your logic
  end
end

# Now you can use
module.call_async(input: "data")
module.with_cache { module.call(input: "data") }
```

### Class Methods as Configuration

```ruby
class CustomModule < Desiru::Module
  # Class-level configuration
  signature "question -> answer"
  model :gpt4
  temperature 0.3
  
  # Instead of instance configuration
  def initialize
    super
    @signature = Desiru::Signature.new("question -> answer")
    @model = :gpt4
    @temperature = 0.3
  end
end
```

## Metaprogramming Patterns

### Dynamic Method Definition

```ruby
# Define methods based on signature
class DynamicModule < Desiru::Module
  def initialize(signature_str)
    super()
    @signature = Desiru::Signature.new(signature_str)
    
    # Define getter methods for each output field
    @signature.output_fields.each do |field|
      define_singleton_method(field.name) do
        @last_result[field.name]
      end
    end
  end
end
```

### DSL Creation

Ruby excels at creating domain-specific languages:

```ruby
# Define a pipeline DSL
class Pipeline < Desiru::Program
  def self.build(&block)
    pipeline = new
    pipeline.instance_eval(&block)
    pipeline
  end
  
  def step(name, signature)
    @steps ||= {}
    @steps[name] = Desiru::Predict.new(signature)
  end
  
  def flow(*step_names)
    @flow = step_names
  end
end

# Usage
pipeline = Pipeline.build do
  step :classify, "text -> category"
  step :summarize, "text -> summary"
  step :translate, "text -> translation"
  
  flow :classify, :summarize
end
```

## Error Handling

Ruby's error handling is similar but has some differences:

```ruby
# Python DSPy
try:
    result = module(question="test")
except dspy.ModelError as e:
    print(f"Error: {e}")

# Ruby Desiru
begin
  result = module.call(question: "test")
rescue Desiru::ModelError => e
  puts "Error: #{e.message}"
rescue StandardError => e
  # Catch all other errors
  puts "Unexpected: #{e.message}"
ensure
  # Always runs (like finally)
  cleanup_resources
end
```

## Testing Patterns

Ruby's RSpec provides expressive testing:

```ruby
# RSpec style (preferred)
RSpec.describe QAModule do
  let(:module) { described_class.new }
  
  describe '#call' do
    it 'answers questions correctly' do
      result = module.call(question: "What is 2+2?")
      expect(result.answer).to eq("4")
    end
    
    context 'with complex questions' do
      it 'provides reasoning' do
        result = module.call(question: "Why is sky blue?")
        expect(result).to have_key(:reasoning)
      end
    end
  end
end
```

## Performance Patterns

### Lazy Evaluation

```ruby
# Ruby's lazy enumerables
large_dataset.lazy
  .map { |item| expensive_operation(item) }
  .select { |result| result.valid? }
  .first(10)  # Only processes enough items to get 10 results
```

### Memoization

```ruby
class ExpensiveModule < Desiru::Module
  def forward(input:)
    @cache ||= {}
    @cache[input] ||= begin
      # Expensive computation only runs once per input
      expensive_operation(input)
    end
  end
end
```

## Common Gotchas for Python Developers

### 1. Everything is an Object

```ruby
# Even classes are objects
Desiru::Module.class  # => Class
"string".class        # => String
42.class             # => Integer
```

### 2. Implicit Returns

```ruby
def calculate(x, y)
  x + y  # Automatically returned
end
# No need for explicit 'return'
```

### 3. Truthiness

```ruby
# Only nil and false are falsy
if 0          # Truthy! (unlike Python)
  puts "0 is truthy in Ruby"
end

if ""         # Truthy! (unlike Python)
  puts "Empty string is truthy"
end

if []         # Truthy! (unlike Python)
  puts "Empty array is truthy"
end
```

### 4. String Interpolation

```ruby
# Use #{} for interpolation
name = "Ruby"
puts "Hello, #{name}!"  # => "Hello, Ruby!"

# Not %s or .format()
```

### 5. No List Comprehensions

```ruby
# Python
squares = [x**2 for x in range(10) if x % 2 == 0]

# Ruby
squares = (0...10).select(&:even?).map { |x| x**2 }
# Or
squares = (0...10).select { |x| x.even? }.map { |x| x**2 }
```

## Best Practices

1. **Use symbols for options**: `call(temperature: 0.7)` not `call("temperature" => 0.7)`
2. **Prefer blocks for configuration**: Use blocks instead of hash configuration when possible
3. **Follow Ruby naming**: Use snake_case for methods, CamelCase for classes
4. **Leverage method chaining**: Ruby methods often return self for chaining
5. **Use guards early**: `return unless condition` instead of wrapping in if blocks
6. **Prefer composition**: Use modules and composition over deep inheritance

## Resources

- [Ruby Style Guide](https://rubystyle.guide/)
- [Effective Ruby](https://effectiveruby.com/)
- [Ruby Metaprogramming](https://pragprog.com/titles/ppmetr2/metaprogramming-ruby-2/)
- [Desiru Examples](https://github.com/obie/desiru/tree/main/examples)