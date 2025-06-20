# DSPy to Desiru Migration Guide

This guide helps you migrate Python DSPy code to Ruby Desiru. While the core concepts remain the same, there are syntax and pattern differences to understand.

## Quick Reference

| DSPy (Python) | Desiru (Ruby) |
|---------------|---------------|
| `import dspy` | `require 'desiru'` |
| `dspy.OpenAI()` | `Desiru::Models::OpenAI.new()` |
| `dspy.Predict()` | `Desiru::Predict.new()` |
| `module(input="text")` | `module.call(input: "text")` |
| `result.answer` | `result.answer` or `result[:answer]` |
| `dspy.ChainOfThought` | `Desiru::ChainOfThought` |
| `dspy.Module` | `Desiru::Module` |
| `dspy.InputField()` | `Desiru::Field.new()` |

## Basic Migration Examples

### Configuration

**DSPy:**
```python
import dspy

# Configure LM
lm = dspy.OpenAI(model='gpt-3.5-turbo', api_key='...')
dspy.settings.configure(lm=lm)
```

**Desiru:**
```ruby
require 'desiru'

# Configure LM
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    model: 'gpt-3.5-turbo',
    api_key: '...'
  )
end
```

### Simple Prediction

**DSPy:**
```python
# Create predictor
predict = dspy.Predict("question -> answer")

# Use it
result = predict(question="What is the capital of France?")
print(result.answer)
```

**Desiru:**
```ruby
# Create predictor
predict = Desiru::Predict.new("question -> answer")

# Use it
result = predict.call(question: "What is the capital of France?")
puts result.answer
```

### Chain of Thought

**DSPy:**
```python
# Create CoT module
cot = dspy.ChainOfThought("question -> answer")

# Use it
result = cot(question="Why is the sky blue?")
print(f"Reasoning: {result.reasoning}")
print(f"Answer: {result.answer}")
```

**Desiru:**
```ruby
# Create CoT module  
cot = Desiru::ChainOfThought.new("question -> answer")

# Use it
result = cot.call(question: "Why is the sky blue?")
puts "Reasoning: #{result.reasoning}"
puts "Answer: #{result.answer}"
```

## Custom Modules

### Basic Module

**DSPy:**
```python
class RAG(dspy.Module):
    def __init__(self, k=3):
        super().__init__()
        self.retrieve = dspy.Retrieve(k=k)
        self.generate = dspy.ChainOfThought("context, question -> answer")
    
    def forward(self, question):
        context = self.retrieve(question)
        answer = self.generate(context=context, question=question)
        return answer
```

**Desiru:**
```ruby
class RAG < Desiru::Module
  def initialize(k: 3)
    super()
    @retrieve = Desiru::Retrieve.new(k: k)
    @generate = Desiru::ChainOfThought.new("context, question -> answer")
  end
  
  def forward(question:)
    context = @retrieve.call(question)
    @generate.call(context: context, question: question)
  end
end
```

### Module with Multiple Signatures

**DSPy:**
```python
class MultiStepQA(dspy.Module):
    def __init__(self):
        super().__init__()
        self.decompose = dspy.Predict("question -> subquestions: list[str]")
        self.answer = dspy.ChainOfThought("subquestion -> subanswer")
        self.aggregate = dspy.Predict("answers: list[str] -> final_answer")
    
    def forward(self, question):
        subquestions = self.decompose(question=question).subquestions
        answers = [self.answer(subquestion=q).subanswer for q in subquestions]
        return self.aggregate(answers=answers)
```

**Desiru:**
```ruby
class MultiStepQA < Desiru::Module
  def initialize
    super
    @decompose = Desiru::Predict.new("question -> subquestions: list[str]")
    @answer = Desiru::ChainOfThought.new("subquestion -> subanswer")
    @aggregate = Desiru::Predict.new("answers: list[str] -> final_answer")
  end
  
  def forward(question:)
    subquestions = @decompose.call(question: question).subquestions
    answers = subquestions.map do |q|
      @answer.call(subquestion: q).subanswer
    end
    @aggregate.call(answers: answers)
  end
end
```

## Signatures

### Field Definitions

**DSPy:**
```python
from dspy import InputField, OutputField

class QASignature(dspy.Signature):
    """Answer questions with reasoning."""
    
    question = InputField(desc="The question to answer")
    context = InputField(desc="Relevant context", optional=True)
    answer = OutputField(desc="The final answer")
    confidence = OutputField(desc="Confidence score 0-1")
```

**Desiru:**
```ruby
# Using string signature with descriptions
signature = Desiru::Signature.new(
  "question: string, context: string? -> answer: string, confidence: float",
  descriptions: {
    question: "The question to answer",
    context: "Relevant context",
    answer: "The final answer", 
    confidence: "Confidence score 0-1"
  }
)

# Or build programmatically
signature = Desiru::Signature.build do
  input :question, String, "The question to answer"
  input :context, String, "Relevant context", optional: true
  output :answer, String, "The final answer"
  output :confidence, Float, "Confidence score 0-1"
end
```

## Optimizers

### Bootstrap Few-Shot

**DSPy:**
```python
from dspy.teleprompt import BootstrapFewShot

# Create optimizer
optimizer = BootstrapFewShot(
    metric=my_metric,
    max_bootstrapped_demos=3
)

# Compile
compiled_program = optimizer.compile(
    program,
    trainset=train_examples
)
```

**Desiru:**
```ruby
# Create optimizer
optimizer = Desiru::BootstrapFewShot.new(
  metric: my_metric,
  max_bootstrapped_demos: 3
)

# Compile
compiled_program = optimizer.compile(
  program,
  trainset: train_examples
)
```

### Custom Metrics

**DSPy:**
```python
def accuracy_metric(example, prediction, trace=None):
    return example.answer.lower() == prediction.answer.lower()

optimizer = BootstrapFewShot(metric=accuracy_metric)
```

**Desiru:**
```ruby
def accuracy_metric(example, prediction, trace = nil)
  example[:answer].downcase == prediction[:answer].downcase
end

optimizer = Desiru::BootstrapFewShot.new(metric: method(:accuracy_metric))

# Or use a lambda
metric = ->(example, prediction, trace = nil) do
  example[:answer].downcase == prediction[:answer].downcase
end
optimizer = Desiru::BootstrapFewShot.new(metric: metric)
```

## ReAct Agents

**DSPy:**
```python
def search_wikipedia(query: str) -> str:
    # Implementation
    return results

tools = [search_wikipedia]

react = dspy.ReAct("question -> answer", tools=tools)
result = react(question="What is the population of Tokyo?")
```

**Desiru:**
```ruby
class WikipediaSearch
  def self.name
    "search_wikipedia"
  end
  
  def self.description
    "Search Wikipedia. Args: query (string)"
  end
  
  def self.call(query:)
    # Implementation
    results
  end
end

tools = [WikipediaSearch]

react = Desiru::Modules::ReAct.new("question -> answer", tools: tools)
result = react.call(question: "What is the population of Tokyo?")
```

## Async Operations

**DSPy:**
```python
import asyncio

async def run_async():
    result = await predict.acall(question="What is 2+2?")
    return result

# Run
result = asyncio.run(run_async())
```

**Desiru:**
```ruby
# Desiru uses background jobs instead of async/await
result = predict.call_async(question: "What is 2+2?")

# Check status
result.ready?  # => false
result.wait    # Block until ready
result.value   # Get the result
```

## Error Handling

**DSPy:**
```python
try:
    result = module(question="test")
except dspy.OpenAIError as e:
    print(f"API Error: {e}")
except Exception as e:
    print(f"Unexpected error: {e}")
```

**Desiru:**
```ruby
begin
  result = module.call(question: "test")
rescue Desiru::ModelError => e
  puts "API Error: #{e.message}"
rescue StandardError => e
  puts "Unexpected error: #{e.message}"
end
```

## Testing

**DSPy:**
```python
import pytest

def test_qa_module():
    qa = QAModule()
    result = qa(question="What is 2+2?")
    assert result.answer == "4"
    assert isinstance(result.confidence, float)
```

**Desiru:**
```ruby
require 'rspec'

RSpec.describe QAModule do
  let(:qa) { described_class.new }
  
  it 'answers math questions' do
    result = qa.call(question: "What is 2+2?")
    expect(result.answer).to eq("4")
    expect(result.confidence).to be_a(Float)
  end
end
```

## Advanced Patterns

### Dataset Loading

**DSPy:**
```python
from dspy.datasets import HotPotQA

dataset = HotPotQA(train_seed=1, dev_seed=2)
trainset = dataset.train[:100]
devset = dataset.dev[:50]
```

**Desiru:**
```ruby
# Load from JSON/CSV
trainset = JSON.parse(File.read('train.json')).map(&:symbolize_keys)
devset = CSV.read('dev.csv', headers: true).map(&:to_h)

# Or create manually
trainset = [
  { question: "What is 2+2?", answer: "4" },
  { question: "Capital of France?", answer: "Paris" }
]
```

### Assertions

**DSPy:**
```python
dspy.Assert(len(output.answer) > 10, "Answer too short")
dspy.Suggest(output.confidence > 0.8, "Low confidence")
```

**Desiru:**
```ruby
Desiru.assert(output.answer.length > 10, "Answer too short")
Desiru.suggest(output.confidence > 0.8, "Low confidence")
```

## Common Pitfalls

### 1. Method Calling
Always use `.call()` in Ruby:
```ruby
# Wrong
result = module(question: "test")

# Correct  
result = module.call(question: "test")
```

### 2. Keyword Arguments
Ruby requires explicit keyword syntax:
```ruby
# Wrong
module.call("What is 2+2?")

# Correct
module.call(question: "What is 2+2?")
```

### 3. List Comprehensions
Ruby uses blocks instead:
```ruby
# Python
answers = [m(q) for q in questions]

# Ruby
answers = questions.map { |q| m.call(q) }
```

### 4. Import vs Require
```ruby
# Python
from dspy.teleprompt import BootstrapFewShot

# Ruby
require 'desiru'
# All classes are under Desiru:: namespace
```

## Complete Example Migration

Here's a complete DSPy program migrated to Desiru:

**Original DSPy:**
```python
import dspy
from dspy.teleprompt import BootstrapFewShot

class SimplifiedBaleen(dspy.Module):
    def __init__(self, passages_per_hop=3):
        super().__init__()
        self.retrieve = dspy.Retrieve(k=passages_per_hop)
        self.generate_query = dspy.ChainOfThought("context, question -> query")
        self.generate_answer = dspy.ChainOfThought("context, question -> answer")
    
    def forward(self, question):
        context = []
        
        for hop in range(2):
            query = self.generate_query(context=context, question=question).query
            passages = self.retrieve(query).passages
            context = context + passages
        
        return self.generate_answer(context=context, question=question)

# Setup
lm = dspy.OpenAI(model='gpt-3.5-turbo')
rm = dspy.ColBERTv2(url='http://localhost:8893/api/search')
dspy.settings.configure(lm=lm, rm=rm)

# Optimize
baleen = SimplifiedBaleen()
optimizer = BootstrapFewShot(metric=validate_answer)
compiled_baleen = optimizer.compile(baleen, trainset=trainset)
```

**Migrated to Desiru:**
```ruby
require 'desiru'

class SimplifiedBaleen < Desiru::Module
  def initialize(passages_per_hop: 3)
    super()
    @retrieve = Desiru::Retrieve.new(k: passages_per_hop)
    @generate_query = Desiru::ChainOfThought.new("context, question -> query")
    @generate_answer = Desiru::ChainOfThought.new("context, question -> answer")
  end
  
  def forward(question:)
    context = []
    
    2.times do
      query = @generate_query.call(
        context: context, 
        question: question
      ).query
      
      passages = @retrieve.call(query).passages
      context = context + passages
    end
    
    @generate_answer.call(context: context, question: question)
  end
end

# Setup
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    model: 'gpt-3.5-turbo'
  )
  config.retrieval_model = Desiru::Models::ColBERT.new(
    url: 'http://localhost:8893/api/search'
  )
end

# Optimize  
baleen = SimplifiedBaleen.new
optimizer = Desiru::BootstrapFewShot.new(metric: method(:validate_answer))
compiled_baleen = optimizer.compile(baleen, trainset: trainset)
```

## Need Help?

- Review the [Ruby Idioms](Ruby-Idioms) guide
- Check out [Examples](https://github.com/obie/desiru/tree/main/examples)
- Ask questions in [GitHub Discussions](https://github.com/obie/desiru/discussions)
- Report issues on [GitHub Issues](https://github.com/obie/desiru/issues)