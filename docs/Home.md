# Desiru Wiki - Ruby DSPy Framework

Welcome to Desiru (Declarative Self-Improving Ruby), the Ruby implementation of [DSPy](https://dspy.ai/). Build sophisticated AI systems with modular, composable code instead of brittle prompt strings.

## 📚 Documentation Overview

### Getting Started
- [Installation Guide](Installation) - Get Desiru up and running
- [Quick Start Tutorial](Quick-Start) - Build your first Desiru program
- [Core Concepts](Core-Concepts) - Understand the fundamentals

### Learn Desiru
#### Programming
- [Signatures](Signatures) - Define input/output contracts
- [Modules](Modules) - Build composable AI components
- [Programs](Programs) - Combine modules into pipelines
- [Models & Adapters](Models-and-Adapters) - LLM integration

#### Evaluation
- [Testing Strategies](Testing-Strategies) - Test your AI programs
- [Metrics & Validation](Metrics-and-Validation) - Measure performance
- [Assertions](Assertions) - Enforce constraints

#### Optimization
- [Optimizers Overview](Optimizers-Overview) - Improve your programs
- [Bootstrap Few-Shot](Bootstrap-Few-Shot) - Basic optimization
- [Advanced Optimizers](Advanced-Optimizers) - MIPROv2 and beyond

### Tutorials
#### Building Programs
- [Simple Q&A Bot](Tutorial-Simple-QA) - Basic question answering
- [RAG Pipeline](Tutorial-RAG-Pipeline) - Retrieval-augmented generation
- [Multi-Stage Reasoning](Tutorial-Multi-Stage) - Complex reasoning chains
- [ReAct Agents](Tutorial-ReAct-Agents) - Tool-using agents

#### Integration & Deployment
- [REST API with Grape](Tutorial-REST-API) - Build AI-powered APIs
- [GraphQL Integration](Tutorial-GraphQL) - GraphQL schema generation
- [Rails Integration](Tutorial-Rails-Integration) - Use Desiru in Rails apps
- [Background Processing](Tutorial-Background-Jobs) - Async processing with Sidekiq

#### Advanced Topics
- [Custom Modules](Tutorial-Custom-Modules) - Extend Desiru
- [Persistence & Analytics](Tutorial-Persistence) - Track performance
- [Production Best Practices](Production-Guide) - Deploy at scale

### API Reference
- [Desiru::Signature](API-Signature) - Signature API
- [Desiru::Module](API-Module) - Base module class
- [Desiru::Program](API-Program) - Program composition
- [Built-in Modules](API-Modules)
  - [Predict](API-Module-Predict)
  - [ChainOfThought](API-Module-ChainOfThought)
  - [ReAct](API-Module-ReAct)
  - [Retrieve](API-Module-Retrieve)
- [Optimizers](API-Optimizers)
  - [BootstrapFewShot](API-Optimizer-BootstrapFewShot)
  - [MIPROv2](API-Optimizer-MIPROv2)
- [Models](API-Models) - LLM adapters
- [Persistence](API-Persistence) - Database layer
- [API Integrations](API-Integrations) - REST/GraphQL

### Migration & Comparison
- [DSPy to Desiru Migration](Migration-Guide) - Port Python code to Ruby
- [Feature Comparison](Feature-Comparison) - DSPy vs Desiru
- [Ruby Idioms](Ruby-Idioms) - Rubyist's guide to Desiru

### Community
- [Contributing](Contributing) - Help improve Desiru
- [Examples](Examples) - Real-world code examples
- [FAQ](FAQ) - Common questions
- [Roadmap](Roadmap) - What's coming next

## 🚀 Quick Links

- **GitHub**: [github.com/obie/desiru](https://github.com/obie/desiru)
- **RubyGems**: [rubygems.org/gems/desiru](https://rubygems.org/gems/desiru)
- **Issues**: [Report bugs or request features](https://github.com/obie/desiru/issues)

## 💡 Philosophy

Desiru brings DSPy's "programming, not prompting" philosophy to Ruby:
- **Declarative**: Define what you want, not how to prompt for it
- **Self-Improving**: Automatically optimize prompts and examples
- **Ruby-Native**: Leverage Ruby's elegance and ecosystem
- **Production-Ready**: Built for real applications, not just research

Start with our [Quick Start Tutorial](Quick-Start) to see Desiru in action!