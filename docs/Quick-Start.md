# Quick Start Tutorial

Let's build your first Desiru program! This tutorial will walk you through creating a simple question-answering system that demonstrates the core concepts.

## Your First Desiru Program

### Step 1: Basic Question Answering

Create a file called `qa_bot.rb`:

```ruby
require 'desiru'

# Configure Desiru with your OpenAI API key
Desiru.configure do |config|
  config.default_model = Desiru::Models::OpenAI.new(
    api_key: ENV['OPENAI_API_KEY']
  )
end

# Create a simple prediction module
qa = Desiru::Predict.new("question -> answer")

# Ask a question
result = qa.call(question: "What is the capital of France?")
puts result.answer
# Output: "Paris"
```

That's it! You've created your first Desiru program. Let's understand what happened:

1. We defined a **signature** `"question -> answer"` that describes the input/output
2. Desiru automatically generated the prompt and handled the LLM call
3. We got back a structured result with an `answer` field

### Step 2: Adding Chain of Thought Reasoning

Let's make our bot explain its reasoning:

```ruby
# Use ChainOfThought for step-by-step reasoning
reasoner = Desiru::ChainOfThought.new("question -> answer")

result = reasoner.call(question: "What is 2 + 2?")
puts "Answer: #{result.answer}"
puts "Reasoning: #{result.reasoning}"
# Output:
# Answer: 4
# Reasoning: To find 2 + 2, I need to add these two numbers together...
```

### Step 3: Working with Types

Desiru supports typed signatures for better control:

```ruby
# Create a sentiment analyzer with typed output
analyzer = Desiru::Predict.new(
  "text: string -> sentiment: Literal['positive', 'negative', 'neutral']",
  descriptions: {
    text: "The text to analyze",
    sentiment: "The overall sentiment of the text"
  }
)

result = analyzer.call(text: "I love this new framework!")
puts result.sentiment # => "positive"
```

### Step 4: Building a Multi-Step Program

Let's create a more complex program that combines multiple modules:

```ruby
class SmartQA < Desiru::Program
  def initialize
    # First, understand the question
    @classifier = Desiru::Predict.new(
      "question -> category: Literal['factual', 'opinion', 'calculation']"
    )
    
    # Then answer based on the category
    @factual_qa = Desiru::Predict.new("question -> answer")
    @opinion_qa = Desiru::ChainOfThought.new("question -> answer")
    @calculator = Desiru::ChainOfThought.new("question -> answer: float")
  end
  
  def forward(question:)
    # Classify the question
    category = @classifier.call(question: question).category
    
    # Route to appropriate handler
    case category
    when 'factual'
      @factual_qa.call(question: question)
    when 'opinion'
      @opinion_qa.call(question: question)
    when 'calculation'
      @calculator.call(question: question)
    end
  end
end

# Use the program
smart_qa = SmartQA.new
result = smart_qa.call(question: "What is 15% of 200?")
puts result.answer # => 30.0
```

### Step 5: Optimization with Few-Shot Examples

Improve your program's performance with examples:

```ruby
# Create training examples
examples = [
  { question: "What is 2+2?", answer: "4" },
  { question: "What is the capital of Japan?", answer: "Tokyo" },
  { question: "How many days in a week?", answer: "7" }
]

# Create and optimize a module
basic_qa = Desiru::Predict.new("question -> answer")

# Optimize with Bootstrap Few-Shot
optimizer = Desiru::BootstrapFewShot.new(
  metric: :exact_match,
  max_bootstrapped_demos: 3
)

optimized_qa = optimizer.compile(basic_qa, trainset: examples)

# The optimized module now includes examples in its prompts
result = optimized_qa.call(question: "What is 5+5?")
puts result.answer # More likely to give numeric answer: "10"
```

## Complete Example: FAQ Bot

Here's a complete example that ties everything together:

```ruby
require 'desiru'

class FAQBot < Desiru::Program
  def initialize(knowledge_base)
    @knowledge_base = knowledge_base
    
    # Check if question is in FAQ
    @classifier = Desiru::Predict.new(
      "question, faq_questions: list[str] -> in_faq: bool"
    )
    
    # Retrieve relevant FAQ entry
    @retriever = Desiru::Retrieve.new(k: 1)
    
    # Generate answer from FAQ or general knowledge
    @faq_answerer = Desiru::Predict.new(
      "question, faq_entry -> answer"
    )
    
    @general_answerer = Desiru::ChainOfThought.new(
      "question -> answer"
    )
  end
  
  def forward(question:)
    # Check if it's an FAQ
    faq_questions = @knowledge_base.keys
    is_faq = @classifier.call(
      question: question, 
      faq_questions: faq_questions
    ).in_faq
    
    if is_faq
      # Retrieve and use FAQ entry
      relevant = @retriever.call(
        question, 
        index: @knowledge_base.keys
      ).first
      
      @faq_answerer.call(
        question: question,
        faq_entry: @knowledge_base[relevant]
      )
    else
      # Use general knowledge
      @general_answerer.call(question: question)
    end
  end
end

# Create FAQ bot with some knowledge
faq_knowledge = {
  "What are your business hours?" => "We're open Monday-Friday, 9am-5pm EST",
  "How do I reset my password?" => "Click 'Forgot Password' on the login page",
  "What payment methods do you accept?" => "We accept all major credit cards and PayPal"
}

bot = FAQBot.new(faq_knowledge)

# Test with FAQ question
result = bot.call(question: "When are you open?")
puts result.answer
# => "We're open Monday-Friday, 9am-5pm EST"

# Test with general question  
result = bot.call(question: "What is the weather like?")
puts result.answer
# => "I don't have access to current weather data..."
```

## What's Next?

Now that you've built your first Desiru programs, explore:

1. **[Core Concepts](Core-Concepts)** - Deep dive into signatures, modules, and programs
2. **[Built-in Modules](Modules)** - Learn about Predict, ChainOfThought, ReAct, and more
3. **[Optimization](Optimizers-Overview)** - Improve your programs with automatic optimization
4. **[Testing Strategies](Testing-Strategies)** - Write tests for your AI programs
5. **[API Integration](Tutorial-REST-API)** - Expose your programs as APIs

## Tips for Success

1. **Start Simple**: Begin with basic Predict modules before moving to complex programs
2. **Use Types**: Typed signatures help ensure consistent outputs
3. **Iterate**: Start with a working program, then optimize with examples
4. **Test Early**: Write tests to ensure your programs behave correctly
5. **Monitor Performance**: Use persistence to track how your programs perform over time

Happy building with Desiru! 🚀