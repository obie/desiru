#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative '../lib/desiru'
require_relative '../lib/desiru/modules/react'
require 'json'
require 'net/http'

# Example of using ReAct module to build a tool-using agent

# Define some useful tools
class WeatherTool
  def self.name
    "get_weather"
  end
  
  def self.description
    "Get current weather for a city. Args: city (string)"
  end
  
  def self.call(city:)
    # In a real implementation, this would call a weather API
    # For demo purposes, we'll return mock data
    temps = { 
      "Tokyo" => 72, 
      "New York" => 68, 
      "London" => 59,
      "Sydney" => 77
    }
    
    temp = temps[city] || rand(50..85)
    conditions = ["sunny", "partly cloudy", "cloudy", "rainy"].sample
    
    "Current weather in #{city}: #{conditions}, #{temp}°F"
  end
end

class CalculatorTool  
  def self.name
    "calculator"
  end
  
  def self.description
    "Perform calculations. Args: expression (string) - a mathematical expression to evaluate"
  end
  
  def self.call(expression:)
    # Safety note: In production, use a proper expression parser
    # This is just for demonstration
    begin
      # Only allow basic math operations
      if expression =~ /^[\d\s\+\-\*\/\(\)\.]+$/
        result = eval(expression)
        "Result: #{result}"
      else
        "Error: Invalid expression. Only numbers and basic operators allowed."
      end
    rescue => e
      "Error: #{e.message}"
    end
  end
end

class TimeTool
  def self.name
    "get_time"
  end
  
  def self.description
    "Get current time for a timezone. Args: timezone (string) - e.g., 'EST', 'PST', 'GMT'"
  end
  
  def self.call(timezone: "GMT")
    # Simple timezone offset mapping
    offsets = {
      "GMT" => 0,
      "EST" => -5,
      "PST" => -8,
      "JST" => 9,
      "AEST" => 10
    }
    
    offset = offsets[timezone.upcase] || 0
    time = Time.now.utc + (offset * 3600)
    
    "Current time in #{timezone}: #{time.strftime('%Y-%m-%d %H:%M:%S')}"
  end
end

# Configure Desiru
Desiru.configure do |config|
  config.default_model = Desiru::Models::RaixAdapter.new(
    provider: ENV['LLM_PROVIDER'] || 'anthropic',
    model: ENV['LLM_MODEL'] || 'claude-3-haiku-20240307'
  )
end

# Create tools array
tools = [WeatherTool, CalculatorTool, TimeTool]

# Example 1: Weather Query
puts "=== Example 1: Weather Query ==="
weather_agent = Desiru::Modules::ReAct.new(
  'question: string -> answer: string',
  tools: tools,
  max_iterations: 5
)

result = weather_agent.call(
  question: "What's the weather like in Tokyo and New York? Also, what time is it in JST?"
)
puts "Question: What's the weather like in Tokyo and New York? Also, what time is it in JST?"
puts "Answer: #{result[:answer]}"
puts

# Example 2: Multi-step Calculation
puts "=== Example 2: Multi-step Calculation ==="
calc_agent = Desiru::Modules::ReAct.new(
  'problem: string -> solution: string, result: float',
  tools: tools,
  max_iterations: 5
)

result = calc_agent.call(
  problem: "If the temperature in Tokyo is 72°F, what is it in Celsius? (Use formula: C = (F - 32) * 5/9)"
)
puts "Problem: If the temperature in Tokyo is 72°F, what is it in Celsius?"
puts "Solution: #{result[:solution]}"
puts "Result: #{result[:result]}"
puts

# Example 3: Complex Query Requiring Multiple Tools
puts "=== Example 3: Complex Multi-tool Query ==="
complex_agent = Desiru::Modules::ReAct.new(
  'query: string -> summary: string, data: list[string]',
  tools: tools,
  max_iterations: 8
)

result = complex_agent.call(
  query: "I'm planning a trip. Get the weather for London and Sydney, calculate the time difference between GMT and AEST, and tell me what time it is in both cities."
)
puts "Query: Planning a trip - need weather and time info for London and Sydney"
puts "Summary: #{result[:summary]}"
puts "Data points:"
result[:data].each { |point| puts "  - #{point}" }
puts

# Example 4: Tool with Error Handling
puts "=== Example 4: Error Handling ==="
error_agent = Desiru::Modules::ReAct.new(
  'task: string -> result: string, status: string',
  tools: tools,
  max_iterations: 3
)

result = error_agent.call(
  task: "Calculate the result of this expression: 10 / 0"
)
puts "Task: Calculate 10 / 0"
puts "Result: #{result[:result]}"
puts "Status: #{result[:status]}"
puts

# Example 5: Custom Tool Integration
puts "=== Example 5: Custom Tool Integration ==="

# Define a custom database lookup tool
database = {
  "user123" => { name: "Alice", balance: 1500.50 },
  "user456" => { name: "Bob", balance: 2300.75 }
}

lookup_tool = lambda do |user_id:|
  if database.key?(user_id)
    user = database[user_id]
    "User #{user[:name]} has balance: $#{user[:balance]}"
  else
    "User not found"
  end
end

# Create agent with custom tool
custom_agent = Desiru::Modules::ReAct.new(
  'request: string -> response: string, amount: float',
  tools: [
    { name: "lookup_user", function: lookup_tool },
    CalculatorTool
  ],
  max_iterations: 5
)

result = custom_agent.call(
  request: "Look up user123 and calculate 10% of their balance"
)
puts "Request: Look up user123 and calculate 10% of their balance"  
puts "Response: #{result[:response]}"
puts "Amount: #{result[:amount]}"

# Demonstrate trajectory truncation for long conversations
puts "\n=== Trajectory Management ==="
puts "The ReAct module automatically manages long trajectories to fit within context limits."
puts "This ensures the agent can handle extended conversations without exceeding token limits."