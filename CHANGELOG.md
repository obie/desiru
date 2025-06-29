# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2025-06-23

### Added
- **Core Data Containers**: New `Example` and `Prediction` classes for structured data handling in DSPy programs
- **Trace Collection System**: Complete tracing infrastructure with `TraceCollector` and `Traceable` for execution monitoring and debugging
- **Compilation Infrastructure**: New `Compiler` and `CompilerBuilder` classes enabling full DSPy program compilation pipeline
- **ProgramOfThought Module**: Advanced reasoning module that generates and executes code for complex problem solving
- **MIPROv2 Optimizer**: State-of-the-art Bayesian optimization algorithm for automatic prompt and few-shot example optimization
- **BestOfN Module**: Multi-sampling module with configurable selection criteria (confidence, consistency, LLM judge, custom)
- **Comprehensive Integration Tests**: Full test coverage for all new components ensuring reliability and correctness

### Enhanced
- **Module Architecture**: Improved base module system to support advanced tracing and compilation features
- **Optimization Pipeline**: Complete optimization workflow from data collection through model improvement
- **Error Handling**: Robust error recovery and logging throughout the new components

### Technical Improvements
- **Type Safety**: Enhanced type checking and validation across all new modules
- **Performance**: Optimized execution paths for compilation and optimization workflows  
- **Extensibility**: Modular architecture enabling easy addition of new optimizers and reasoning modules

## [0.1.1] - 2025-06-21

### Added
- Direct API client implementations for Anthropic, OpenAI, and OpenRouter
- New modules: Majority, MultiChainComparison, and ProgramOfThought
- New optimizers: COPRO and KNNFewShot
- Enhanced error handling with detailed error classes
- Support for Ruby 3.3.6 (minimum version now 3.3.0)
- Interactive console with pre-loaded modules (`bin/console`)
- Examples runner with model selection (`bin/examples`)

### Changed
- Replaced Raix dependency with direct API integrations for better control
- Improved console experience with better error messages and debug helpers
- Updated default max_tokens from 1000 to 4096 to prevent truncated responses
- Fixed namespace issues in console by including necessary modules

### Fixed
- Redis mocking in job tests for CI compatibility
- Rubocop configuration to match required Ruby version
- Test failures in CI environment

### Removed
- Raix gem dependency
- Support for Ruby 3.2.x (minimum version is now 3.3.0)

## [0.1.0] - 2025-06-12

### Added
- Initial release of Desiru
- Core DSPy functionality ported to Ruby
- Basic modules: Predict, ChainOfThought, ReAct
- Signature system with type validation
- Model adapters for OpenAI and Anthropic (via Raix)
- Optimizers: BootstrapFewShot, MIPROv2
- REST API integration with Grape and Sinatra
- GraphQL integration with automatic schema generation
- Background job processing with Sidekiq
- Database persistence layer with Sequel
- Comprehensive test suite
- Documentation and examples

[0.2.0]: https://github.com/obie/desiru/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/obie/desiru/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/obie/desiru/releases/tag/v0.1.0