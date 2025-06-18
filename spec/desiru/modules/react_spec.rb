# frozen_string_literal: true

require 'spec_helper'
require 'desiru/modules/react'

RSpec.describe Desiru::Modules::ReAct do
  let(:mock_model) { double('model') }
  let(:signature) { Desiru::Signature.new('question: string -> answer: string') }
  let(:weather_tool) do
    lambda do |city:|
      "The weather in #{city} is sunny with a temperature of 72°F."
    end
  end
  
  let(:calculator_tool) do
    lambda do |operation:, a:, b:|
      case operation
      when 'add' then a + b
      when 'multiply' then a * b
      when 'divide' then b != 0 ? a.to_f / b : 'Error: Division by zero'
      else "Unknown operation: #{operation}"
      end
    end
  end
  
  let(:tools) do
    [
      { name: 'get_weather', function: weather_tool },
      { name: 'calculator', function: calculator_tool }
    ]
  end
  
  let(:react_module) { described_class.new(signature, tools: tools, max_iterations: 3, model: mock_model) }

  describe '#initialize' do
    it 'creates a ReAct module with tools' do
      expect(react_module).to be_a(described_class)
      expect(react_module.max_iterations).to eq(3)
      expect(react_module.tools).to include('get_weather', 'calculator', 'finish')
    end

    it 'normalizes various tool formats' do
      # Test with array format
      array_tools = [
        ['tool1', -> { 'result1' }],
        ['tool2', -> { 'result2' }]
      ]
      module1 = described_class.new(signature, tools: array_tools, model: mock_model)
      expect(module1.tools.keys).to include('tool1', 'tool2', 'finish')
      
      # Test with hash format
      hash_tools = [
        { 'name' => 'tool3', 'function' => -> { 'result3' } }
      ]
      module2 = described_class.new(signature, tools: hash_tools, model: mock_model)
      expect(module2.tools.keys).to include('tool3', 'finish')
    end
  end

  describe '#forward' do
    context 'with mocked chain of thought' do
      before do
        # Mock the ChainOfThought modules to control the flow
        allow_any_instance_of(Desiru::Modules::ChainOfThought).to receive(:call) do |_, inputs|
          if inputs.key?(:trajectory)
            trajectory = inputs[:trajectory]
            
            if trajectory == "No actions taken yet."
              # First iteration: ask for weather
              {
                next_thought: "I need to check the weather in Tokyo.",
                next_tool_name: "get_weather",
                next_tool_args: '{"city": "Tokyo"}'
              }
            elsif trajectory.include?("get_weather") && !trajectory.include?("finish")
              # Second iteration: finish with the weather info
              {
                next_thought: "I now have the weather information for Tokyo.",
                next_tool_name: "finish",
                next_tool_args: '{}'
              }
            else
              # Extract phase: return the answer
              {
                answer: "The weather in Tokyo is sunny with a temperature of 72°F."
              }
            end
          else
            # Should not reach here in normal flow
            { answer: "Unknown state" }
          end
        end
      end

      it 'executes tools and produces output' do
        result = react_module.call(question: "What's the weather in Tokyo?")
        
        expect(result[:answer]).to include("weather in Tokyo")
        expect(result[:answer]).to include("sunny")
        expect(result[:answer]).to include("72°F")
      end
    end

    context 'with calculation task' do
      before do
        step = 0
        allow_any_instance_of(Desiru::Modules::ChainOfThought).to receive(:call) do |instance, inputs|
          
          # Check what outputs this instance expects
          expected_outputs = instance.signature.output_fields.keys
          
          if expected_outputs.include?('next_thought')
            # React phase - we're selecting tools
            step += 1
            case step
            when 1
              # First calculation
              {
                next_thought: "I need to calculate 15 * 8.",
                next_tool_name: "calculator",
                next_tool_args: '{"operation": "multiply", "a": 15, "b": 8}'
              }
            when 2
              # Second calculation
              {
                next_thought: "Now I'll add 25 to the result.",
                next_tool_name: "calculator", 
                next_tool_args: '{"operation": "add", "a": 120, "b": 25}'
              }
            when 3
              # Finish
              {
                next_thought: "I have the final result.",
                next_tool_name: "finish",
                next_tool_args: '{}'
              }
            else
              # Should not reach here
              {
                next_thought: "Done",
                next_tool_name: "finish",
                next_tool_args: '{}'
              }
            end
          else
            # Extract phase - return answer
            {
              answer: "The result of (15 * 8) + 25 is 145."
            }
          end
        end
      end

      it 'performs multi-step calculations' do
        result = react_module.call(question: "What is (15 * 8) + 25?")
        
        expect(result[:answer]).to include("145")
      end
    end

    context 'with tool errors' do
      let(:error_tool) do
        lambda do |**args|
          raise "Tool error: Something went wrong"
        end
      end
      
      let(:tools) { [{ name: 'error_tool', function: error_tool }] }

      before do
        allow_any_instance_of(Desiru::Modules::ChainOfThought).to receive(:call) do |instance, inputs|
          expected_outputs = instance.signature.output_fields.keys
          
          if expected_outputs.include?('next_thought')
            trajectory = inputs[:trajectory]
            
            if trajectory == "No actions taken yet."
              {
                next_thought: "I'll use the error tool.",
                next_tool_name: "error_tool",
                next_tool_args: '{}'
              }
            elsif trajectory.include?("Error:")
              {
                next_thought: "The tool failed, but I'll finish anyway.",
                next_tool_name: "finish",
                next_tool_args: '{}'
              }
            else
              {
                next_thought: "Finishing",
                next_tool_name: "finish",
                next_tool_args: '{}'
              }
            end
          else
            # Extract phase
            {
              answer: "The tool encountered an error, but the task was completed."
            }
          end
        end
      end

      it 'handles tool execution errors gracefully' do
        result = react_module.call(question: "Test error handling")
        
        expect(result[:answer]).to include("error")
        expect { result }.not_to raise_error
      end
    end

    context 'with max iterations' do
      let(:react_module) { described_class.new(signature, tools: tools, max_iterations: 2, model: mock_model) }

      before do
        iteration = 0
        allow_any_instance_of(Desiru::Modules::ChainOfThought).to receive(:call) do |instance, inputs|
          expected_outputs = instance.signature.output_fields.keys
          
          if expected_outputs.include?('next_thought')
            iteration += 1
            
            # Never call finish, just keep using tools
            {
              next_thought: "Iteration #{iteration}",
              next_tool_name: "get_weather",
              next_tool_args: '{"city": "City' + iteration.to_s + '"}'
            }
          else
            # Extract phase after max iterations
            {
              answer: "Reached maximum iterations"
            }
          end
        end
      end

      it 'stops after max iterations' do
        result = react_module.call(question: "Keep going forever")
        
        expect(result[:answer]).to eq("Reached maximum iterations")
      end
    end
  end

  describe '#parse_tool_args' do
    it 'parses JSON arguments' do
      args = react_module.send(:parse_tool_args, '{"city": "Tokyo", "units": "fahrenheit"}')
      expect(args).to eq({ city: "Tokyo", units: "fahrenheit" })
    end

    it 'parses simple key:value arguments' do
      args = react_module.send(:parse_tool_args, 'city: Tokyo, temp: 25')
      expect(args).to eq({ city: "Tokyo", temp: 25 })
    end

    it 'parses key=value arguments' do
      args = react_module.send(:parse_tool_args, 'operation=add, a=10, b=5')
      expect(args).to eq({ operation: "add", a: 10, b: 5 })
    end

    it 'handles empty arguments' do
      expect(react_module.send(:parse_tool_args, '')).to eq({})
      expect(react_module.send(:parse_tool_args, nil)).to eq({})
    end

    it 'converts types appropriately' do
      args = react_module.send(:parse_tool_args, 'flag: true, count: 42, rate: 3.14')
      expect(args).to eq({ flag: true, count: 42, rate: 3.14 })
    end
  end

  describe '#format_trajectory' do
    it 'formats empty trajectory' do
      formatted = react_module.send(:format_trajectory, [])
      expect(formatted).to eq("No actions taken yet.")
    end

    it 'formats trajectory with steps' do
      trajectory = [
        {
          thought: "I need weather info",
          tool: "get_weather",
          args: { city: "Tokyo" },
          observation: "Sunny, 72°F"
        },
        {
          thought: "Got the info",
          tool: "finish",
          args: {}
        }
      ]
      
      formatted = react_module.send(:format_trajectory, trajectory)
      expect(formatted).to include("Step 1:")
      expect(formatted).to include("Thought: I need weather info")
      expect(formatted).to include("Tool: get_weather")
      expect(formatted).to include("Observation: Sunny, 72°F")
      expect(formatted).to include("Step 2:")
    end
  end

  describe '#truncate_trajectory' do
    it 'keeps trajectory under max length' do
      long_trajectory = Array.new(10) do |i|
        {
          thought: "A very long thought that contains lots of text " * 20,
          tool: "tool#{i}",
          args: { param: "value#{i}" },
          observation: "A very long observation " * 20
        }
      end
      
      truncated = react_module.send(:truncate_trajectory, long_trajectory, max_length: 1000)
      formatted = react_module.send(:format_trajectory, truncated)
      
      expect(formatted.length).to be <= 1000
      expect(truncated.length).to be < long_trajectory.length
    end

    it 'returns original trajectory if under limit' do
      short_trajectory = [
        { thought: "Quick thought", tool: "finish", args: {} }
      ]
      
      truncated = react_module.send(:truncate_trajectory, short_trajectory)
      expect(truncated).to eq(short_trajectory)
    end
  end

  describe 'integration with real tools' do
    let(:search_results) { [] }
    let(:search_tool) do
      results = search_results # Capture in closure
      lambda do |query:|
        results.find { |r| r[:title].downcase.include?(query.downcase) } || 
          { title: "No results found", content: "Try a different query" }
      end
    end
    
    let(:tools) do
      [{ name: 'search', function: search_tool }]
    end

    before do
      search_results << { title: "Ruby Programming", content: "Ruby is a dynamic language" }
      search_results << { title: "Python Guide", content: "Python is great for data science" }
      
      allow_any_instance_of(Desiru::Modules::ChainOfThought).to receive(:call) do |instance, inputs|
        expected_outputs = instance.signature.output_fields.keys
        
        if expected_outputs.include?('next_thought')
          trajectory = inputs[:trajectory]
          
          if trajectory == "No actions taken yet."
            {
              next_thought: "I'll search for Ruby information.",
              next_tool_name: "search",
              next_tool_args: '{"query": "Ruby"}'
            }
          elsif trajectory.include?("Ruby is a dynamic language")
            {
              next_thought: "Found information about Ruby.",
              next_tool_name: "finish",
              next_tool_args: '{}'
            }
          else
            {
              next_thought: "Searching",
              next_tool_name: "search",
              next_tool_args: '{"query": "programming"}'
            }
          end
        else
          # Extract phase
          {
            answer: "Ruby is a dynamic programming language."
          }
        end
      end
    end

    it 'integrates with custom tools' do
      result = react_module.call(question: "Tell me about Ruby")
      
      expect(result[:answer]).to include("Ruby")
      expect(result[:answer]).to include("dynamic")
    end
  end
end