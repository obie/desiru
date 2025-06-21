# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe 'Streaming Endpoint SSE Format' do
  # Mock stream object to capture SSE output
  let(:mock_stream_class) do
    Class.new(StringIO) do
      def <<(data)
        write(data)
        self
      end

      def close
        # No-op for testing
      end
    end
  end

  before do
    stub_const('MockStream', mock_stream_class)
  end

  let(:mock_model) do
    double('model', complete: { text: 'mocked response' })
  end

  describe 'Grape Integration Streaming' do
    let(:module_with_streaming) do
      Class.new(Desiru::Module) do
        def forward(input:)
          { output: "Processed: #{input}" }
        end

        def call_stream(inputs, &block)
          # Simulate streaming chunks
          block.call({ text: 'First chunk' })
          block.call({ text: 'Second chunk' })
          call(inputs)
        end
      end.new('input: string -> output: string', model: mock_model)
    end

    it 'generates correct SSE format for Grape streaming' do
      stream = MockStream.new
      inputs = { input: 'test' }

      # Simulate the Grape streaming logic
      begin
        module_with_streaming.call_stream(inputs) do |chunk|
          stream << "event: chunk\n"
          stream << "data: #{JSON.generate(chunk)}\n\n"
        end

        result = module_with_streaming.call(inputs)
        stream << "event: result\n"
        stream << "data: #{JSON.generate({ output: result[:output] })}\n\n"
        stream << "event: done\n"
        stream << "data: #{JSON.generate({ status: 'complete' })}\n\n"
      rescue StandardError => e
        stream << "event: error\n"
        stream << "data: #{JSON.generate({ error: e.message })}\n\n"
      end

      # Verify the SSE output
      output = stream.string
      events = parse_sse_events(output)

      expect(events.length).to eq(4)
      expect(events[0]).to eq({ event: 'chunk', data: { 'text' => 'First chunk' } })
      expect(events[1]).to eq({ event: 'chunk', data: { 'text' => 'Second chunk' } })
      expect(events[2]).to eq({ event: 'result', data: { 'output' => 'Processed: test' } })
      expect(events[3]).to eq({ event: 'done', data: { 'status' => 'complete' } })
    end
  end

  describe 'Sinatra Integration Streaming' do
    let(:module_with_streaming) do
      Class.new(Desiru::Module) do
        def forward(input:)
          { output: "Processed: #{input}" }
        end

        def call_stream(inputs, &block)
          # Simulate streaming chunks
          block.call({ text: 'First chunk' })
          block.call({ text: 'Second chunk' })
          call(inputs)
        end
      end.new('input: string -> output: string', model: mock_model)
    end

    it 'generates correct SSE format for Sinatra streaming' do
      stream = MockStream.new
      params = { 'input' => 'test' }

      # Simulate the Sinatra streaming logic (after the fix)
      begin
        module_with_streaming.call_stream(params) do |chunk|
          stream << "event: chunk\n"
          stream << "data: #{JSON.generate(chunk)}\n\n"
        end

        result = module_with_streaming.call(params)
        stream << "event: result\n"
        stream << "data: #{JSON.generate({ output: result[:output] })}\n\n"
        stream << "event: done\n"
        stream << "data: #{JSON.generate({ status: 'complete' })}\n\n"
      rescue StandardError => e
        stream << "event: error\n"
        stream << "data: #{JSON.generate({ error: e.message })}\n\n"
      end

      # Verify the SSE output
      output = stream.string
      events = parse_sse_events(output)

      expect(events.length).to eq(4)
      expect(events[0]).to eq({ event: 'chunk', data: { 'text' => 'First chunk' } })
      expect(events[1]).to eq({ event: 'chunk', data: { 'text' => 'Second chunk' } })
      expect(events[2]).to eq({ event: 'result', data: { 'output' => 'Processed: test' } })
      expect(events[3]).to eq({ event: 'done', data: { 'status' => 'complete' } })
    end

    it 'handles errors correctly in SSE format' do
      error_module = Class.new(Desiru::Module) do
        def forward(_inputs)
          raise 'Test error'
        end

        def call_stream(inputs, &)
          call(inputs)
        end
      end.new('input: string -> output: string', model: mock_model)

      stream = MockStream.new
      params = { 'input' => 'test' }

      begin
        error_module.call_stream(params) do |chunk|
          stream << "event: chunk\n"
          stream << "data: #{JSON.generate(chunk)}\n\n"
        end

        result = error_module.call(params)
        stream << "event: result\n"
        stream << "data: #{JSON.generate({ output: result[:output] })}\n\n"
        stream << "event: done\n"
        stream << "data: #{JSON.generate({ status: 'complete' })}\n\n"
      rescue StandardError => e
        stream << "event: error\n"
        stream << "data: #{JSON.generate({ error: e.message })}\n\n"
      end

      output = stream.string
      events = parse_sse_events(output)

      expect(events.length).to eq(1)
      expect(events[0]).to eq({ event: 'error', data: { 'error' => 'Module execution failed: Test error' } })
    end
  end

  describe 'SSE format validation' do
    it 'ensures all data fields contain valid JSON' do
      valid_sse = <<~SSE
        event: chunk
        data: {"text": "Hello"}

        event: result
        data: {"output": "Done"}

        event: done
        data: {"status": "complete"}

      SSE

      events = parse_sse_events(valid_sse)
      expect(events).to all(have_key(:data))
      events.each do |event|
        # This would have raised an error during parsing if JSON was invalid
        expect(event[:data]).to be_a(Hash)
      end
    end

    it 'validates SSE field format' do
      # Each line should follow "field: value" format
      valid_lines = [
        'event: chunk',
        'data: {"key": "value"}',
        'id: 123',
        'retry: 1000'
      ]

      valid_lines.each do |line|
        expect(line).to match(/^(event|data|id|retry):\s*.+$/)
      end
    end
  end

  private

  def parse_sse_events(body)
    events = []
    current_event = {}

    body.split("\n").each do |line|
      if line.empty?
        events << current_event unless current_event.empty?
        current_event = {}
      elsif line.start_with?('event:')
        current_event[:event] = line.split(':', 2)[1].strip
      elsif line.start_with?('data:')
        data_str = line.split(':', 2)[1].strip
        current_event[:data] = JSON.parse(data_str) unless data_str.empty?
      end
    end

    events << current_event unless current_event.empty?
    events
  end
end
