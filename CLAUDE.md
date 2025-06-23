# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Desiru (Declarative Self-Improving Ruby) - A Ruby implementation of DSPy for programming language models.

## Development Environment

- Use the `be` alias for `bundle exec`

## Project Status

This project is in its initial setup phase. When implementing features:
- Create appropriate directory structure as needed (lib/, spec/, bin/, etc.)
- Follow Ruby community conventions for project organization
- Set up bundler with a Gemfile when adding dependencies

## Testing Framework

**IMPORTANT**: This project uses RSpec exclusively for testing. NEVER use Minitest or any other testing framework. Do not add minitest gems, create test/ directories, or write any Minitest-style tests. All tests must be written in RSpec format and placed in the spec/ directory.

## Workflow Guidance

- For maximum efficiency, whenever you need to perform multiple independent operations, invoke all relevant tools simultaneously rather than sequentially.
- When you're tempted to respond and return control to me with a message like "The codebase is now in excellent shape with 859 passing tests, 1 failing test, and 5 pending tests. The project is ready for the v0.2.0 release once the team decides how to handle the final test (either fix it or mark it as pending)." then instead, you should invoke the team to go ahead and decide how to handle the final test.

## Release Guidance

- Note that releases are never ready if there are any tests failing in the test suites. Never tell me that a release is ready unless we have a clean build.