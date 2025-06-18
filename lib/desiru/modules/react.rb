# frozen_string_literal: true

require_relative '../module'
require_relative 'chain_of_thought'

module Desiru
  module Modules
    # ReAct (Reasoning and Acting) module for tool-using AI agents
    # This module allows the language model to iteratively reason about a task
    # and use tools to gather information before producing a final answer
    class ReAct < Desiru::Module
      attr_reader :max_iterations, :tools, :react_module, :extract_module

      def initialize(signature, tools: [], max_iterations: 5, model: nil)
        super(signature, model: model)
        @tools = normalize_tools(tools)
        @max_iterations = max_iterations
        
        # Build the ReAct signature for reasoning and tool selection
        react_signature = build_react_signature
        @react_module = ChainOfThought.new(react_signature, model: @model)
        
        # Build extraction signature for final output
        extract_signature = build_extract_signature
        @extract_module = ChainOfThought.new(extract_signature, model: @model)
      end

      def forward(inputs)
        trajectory = []
        
        max_iterations.times do |iteration|
          # Get the next action from the model
          react_inputs = prepare_react_inputs(inputs, trajectory)
          react_output = react_module.call(react_inputs)
          
          # Extract the tool name and arguments
          tool_name = react_output[:next_tool_name]
          tool_args = parse_tool_args(react_output[:next_tool_args])
          
          # Add reasoning to trajectory
          trajectory << {
            thought: react_output[:next_thought],
            tool: tool_name,
            args: tool_args
          }
          
          # Check if we're done
          if tool_name == "finish"
            break
          end
          
          # Execute the tool
          begin
            tool_result = execute_tool(tool_name, tool_args)
            trajectory.last[:observation] = tool_result
          rescue => e
            trajectory.last[:observation] = "Error: #{e.message}"
          end
        end
        
        # Extract final outputs from trajectory
        extract_inputs = prepare_extract_inputs(inputs, trajectory)
        extract_module.call(extract_inputs)
      end

      private

      def normalize_tools(tools)
        # Convert tools to a consistent format
        normalized = {}
        
        tools.each do |tool|
          case tool
          when Hash
            # Assume hash has name and function keys
            normalized[tool[:name] || tool["name"]] = tool[:function] || tool["function"]
          when Array
            # Assume array of [name, function] pairs
            name, function = tool
            normalized[name] = function
          else
            # Assume it's a callable with a name method
            if tool.respond_to?(:name) && tool.respond_to?(:call)
              normalized[tool.name] = tool
            elsif tool.is_a?(Method) || tool.is_a?(Proc)
              # Use the method/proc name or generate one
              name = tool.respond_to?(:name) ? tool.name.to_s : "tool_#{normalized.size}"
              normalized[name] = tool
            end
          end
        end
        
        # Always include the finish tool
        normalized["finish"] = -> { "Task completed" }
        
        normalized
      end

      def build_react_signature
        # Build signature for reasoning and tool selection
        input_fields = signature.input_fields.keys.join(", ")
        
        # Create the ReAct signature
        react_sig = "#{input_fields}, trajectory -> next_thought, next_tool_name, next_tool_args"
        
        # Add instructions
        instructions = <<~INST
          You are an AI agent that can use tools to accomplish tasks.
          
          Available tools:
          #{format_tool_descriptions}
          
          Based on the input and trajectory so far, reason about what to do next.
          Then select a tool to use and provide the arguments for that tool.
          
          When you have gathered enough information to answer the question,
          use the "finish" tool to complete the task.
        INST
        
        Signature.new(react_sig, descriptions: { 'next_thought' => instructions })
      end

      def build_extract_signature
        # Build signature for extracting final outputs
        input_fields = signature.input_fields.keys.join(", ")
        output_fields = signature.output_fields.keys.join(", ")
        
        extract_sig = "#{input_fields}, trajectory -> #{output_fields}"
        
        instructions = <<~INST
          Based on the trajectory of thoughts and tool observations,
          extract the final #{output_fields} to answer the original question.
        INST
        
        Signature.new(extract_sig, descriptions: { output_fields => instructions })
      end

      def format_tool_descriptions
        tools.map do |name, function|
          if name == "finish"
            "- finish: Mark the task as complete when you have enough information"
          else
            # Try to extract description from function
            desc = if function.respond_to?(:description)
                     function.description
                   elsif function.respond_to?(:to_s)
                     function.to_s
                   else
                     "Tool: #{name}"
                   end
            "- #{name}: #{desc}"
          end
        end.join("\n")
      end

      def prepare_react_inputs(inputs, trajectory)
        inputs.merge(
          trajectory: format_trajectory(trajectory)
        )
      end

      def prepare_extract_inputs(inputs, trajectory)
        inputs.merge(
          trajectory: format_trajectory(trajectory)
        )
      end

      def format_trajectory(trajectory)
        return "No actions taken yet." if trajectory.empty?
        
        trajectory.map.with_index do |step, i|
          parts = ["Step #{i + 1}:"]
          parts << "Thought: #{step[:thought]}" if step[:thought]
          parts << "Tool: #{step[:tool]}" if step[:tool]
          parts << "Args: #{step[:args]}" if step[:args] && !step[:args].empty?
          parts << "Observation: #{step[:observation]}" if step[:observation]
          parts.join("\n")
        end.join("\n\n")
      end

      def parse_tool_args(args_string)
        # Parse tool arguments from string format
        return {} if args_string.nil? || args_string.strip.empty?
        
        # Try to parse as JSON first
        begin
          require 'json'
          JSON.parse(args_string, symbolize_names: true)
        rescue JSON::ParserError
          # Fallback: parse simple key:value pairs
          parse_simple_args(args_string)
        end
      end

      def parse_simple_args(args_string)
        # Parse simple key:value format
        args = {}
        
        # Match patterns like key:value or key=value
        args_string.scan(/(\w+)[:=]\s*([^,]+)/).each do |key, value|
          # Clean up the value
          value = value.strip.gsub(/^["']|["']$/, '') # Remove quotes
          
          # Try to convert to appropriate type
          args[key.to_sym] = case value.downcase
                             when 'true' then true
                             when 'false' then false
                             when /^\d+$/ then value.to_i
                             when /^\d+\.\d+$/ then value.to_f
                             else value
                             end
        end
        
        args
      end

      def execute_tool(tool_name, args)
        tool = tools[tool_name]
        
        raise "Unknown tool: #{tool_name}" unless tool
        
        # Call the tool with arguments
        if tool.arity == 0
          tool.call
        elsif tool.arity == 1 && args.is_a?(Hash)
          # Pass args as keyword arguments if possible
          if tool.respond_to?(:parameters)
            param_types = tool.parameters.map(&:first)
            if param_types.include?(:keyreq) || param_types.include?(:key)
              tool.call(**args)
            else
              tool.call(args)
            end
          else
            tool.call(args)
          end
        else
          # Pass args as positional arguments
          tool.call(*args.values)
        end
      end

      # Support for truncating trajectory if it gets too long
      def truncate_trajectory(trajectory, max_length: 3000)
        formatted = format_trajectory(trajectory)
        
        return trajectory if formatted.length <= max_length
        
        # Remove oldest steps until we're under the limit
        truncated = trajectory.dup
        
        # Keep removing the oldest steps until we're under the limit
        while truncated.length > 1
          truncated_formatted = format_trajectory(truncated)
          break if truncated_formatted.length <= max_length
          truncated.shift
        end
        
        # If even a single step is too long, truncate its content
        if truncated.length == 1 && format_trajectory(truncated).length > max_length
          step = truncated[0]
          # Truncate the observation if it exists and is long
          if step[:observation] && step[:observation].length > 100
            step[:observation] = step[:observation][0..100] + "... (truncated)"
          end
          # Truncate thought if it's very long
          if step[:thought] && step[:thought].length > 100
            step[:thought] = step[:thought][0..100] + "... (truncated)"
          end
        end
        
        truncated
      end
    end
  end
end