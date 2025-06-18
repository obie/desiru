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