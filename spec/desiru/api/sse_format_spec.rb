# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'SSE Format Validation' do
  describe 'Server-Sent Events format' do
    def validate_sse_format(data)
      # SSE format rules:
      # - Events are separated by double newlines
      # - Each event can have multiple fields
      # - Fields are: event, data, id, retry
      # - Each field is "name: value\n"
      # - Data fields must contain valid JSON

      events = data.split("\n\n").reject(&:empty?)
      parsed_events = []

      events.each do |event|
        parsed_event = {}
        lines = event.split("\n")

        lines.each do |line|
          next if line.empty?

          match = line.match(/^(event|data|id|retry):\s*(.*)$/)
          expect(match).not_to be_nil, "Invalid SSE line format: #{line}"

          field_name = match[1]
          field_value = match[2]

          if field_name == 'data' && !field_value.empty?
            # Data should be valid JSON
            expect { JSON.parse(field_value) }.not_to raise_error
          end

          parsed_event[field_name] = field_value
        end

        parsed_events << parsed_event
      end

      parsed_events
    end

    it 'generates valid SSE format for result event' do
      sse_data = <<~SSE
        event: result
        data: {"output": "test result"}

        event: done
        data: {"status": "complete"}

      SSE

      events = validate_sse_format(sse_data)
      expect(events.length).to eq(2)

      result_event = events.find { |e| e['event'] == 'result' }
      expect(result_event).not_to be_nil
      expect(JSON.parse(result_event['data'])).to eq({ 'output' => 'test result' })

      done_event = events.find { |e| e['event'] == 'done' }
      expect(done_event).not_to be_nil
      expect(JSON.parse(done_event['data'])).to eq({ 'status' => 'complete' })
    end

    it 'generates valid SSE format for streaming chunks' do
      sse_data = <<~SSE
        event: chunk
        data: {"text": "First chunk"}

        event: chunk
        data: {"text": "Second chunk"}

        event: result
        data: {"output": "Complete response"}

        event: done
        data: {"status": "complete"}

      SSE

      events = validate_sse_format(sse_data)
      expect(events.length).to eq(4)

      chunks = events.select { |e| e['event'] == 'chunk' }
      expect(chunks.length).to eq(2)
      expect(JSON.parse(chunks[0]['data'])).to eq({ 'text' => 'First chunk' })
      expect(JSON.parse(chunks[1]['data'])).to eq({ 'text' => 'Second chunk' })
    end

    it 'generates valid SSE format for errors' do
      sse_data = <<~SSE
        event: error
        data: {"error": "Something went wrong"}

      SSE

      events = validate_sse_format(sse_data)
      expect(events.length).to eq(1)

      error_event = events.first
      expect(error_event['event']).to eq('error')
      expect(JSON.parse(error_event['data'])).to eq({ 'error' => 'Something went wrong' })
    end

    it 'rejects invalid SSE format' do
      # Missing colon
      expect { validate_sse_format("event result\n") }.to raise_error(RSpec::Expectations::ExpectationNotMetError)

      # Invalid JSON in data field
      expect { validate_sse_format("event: test\ndata: not json\n") }.to raise_error(RSpec::Expectations::ExpectationNotMetError)
    end
  end

  describe 'SSE format helper' do
    class SSEFormatter
      def self.format_event(event_type, data)
        output = []
        output << "event: #{event_type}"
        output << "data: #{JSON.generate(data)}"
        output.join("\n") + "\n\n"
      end

      def self.format_chunk(chunk_data)
        format_event('chunk', chunk_data)
      end

      def self.format_result(result_data)
        format_event('result', result_data)
      end

      def self.format_done
        format_event('done', { status: 'complete' })
      end

      def self.format_error(error_message)
        format_event('error', { error: error_message })
      end
    end

    it 'formats events correctly' do
      expect(SSEFormatter.format_chunk({ text: 'Hello' })).to eq(
        "event: chunk\ndata: {\"text\":\"Hello\"}\n\n"
      )

      expect(SSEFormatter.format_result({ output: 'Done' })).to eq(
        "event: result\ndata: {\"output\":\"Done\"}\n\n"
      )

      expect(SSEFormatter.format_done).to eq(
        "event: done\ndata: {\"status\":\"complete\"}\n\n"
      )

      expect(SSEFormatter.format_error('Failed')).to eq(
        "event: error\ndata: {\"error\":\"Failed\"}\n\n"
      )
    end
  end

  describe 'Integration test helpers' do
    # Helper to parse SSE response body
    def parse_sse_response(body)
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

    it 'parses SSE responses correctly' do
      sample_response = "event: result\ndata: {\"output\":\"test\"}\n\nevent: done\ndata: {\"status\":\"complete\"}\n\n"
      events = parse_sse_response(sample_response)

      expect(events.length).to eq(2)
      expect(events[0]).to eq({ event: 'result', data: { 'output' => 'test' } })
      expect(events[1]).to eq({ event: 'done', data: { 'status' => 'complete' } })
    end
  end
end
