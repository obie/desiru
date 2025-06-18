# Desiru Examples

This directory contains example scripts demonstrating various features of Desiru.

## Running the Examples

Before running any examples, make sure you have:

1. Installed the gem dependencies:
   ```bash
   bundle install
   ```

2. Set your OpenAI API key:
   ```bash
   export OPENAI_API_KEY="your-api-key-here"
   ```

## Available Examples

### simple_qa.rb
Basic question-answering using the Predict and ChainOfThought modules.

```bash
ruby examples/simple_qa.rb
```

### typed_signatures.rb
Demonstrates typed signatures with input/output validation and field descriptions.

```bash
ruby examples/typed_signatures.rb
```

### few_shot_learning.rb
Shows how to use the BootstrapFewShot optimizer to improve module performance with training examples.

```bash
ruby examples/few_shot_learning.rb
```

## Creating Your Own Examples

When creating new examples:

1. Use `require "bundler/setup"` to ensure proper gem loading
2. Configure Desiru with your preferred model
3. Create modules with appropriate signatures
4. Handle API keys securely (use environment variables)

## Notes

- These examples use OpenAI by default, but you can configure other providers (Anthropic, OpenRouter, etc.)
- Make sure to handle API rate limits appropriately in production code
- Consider caching results for expensive operations