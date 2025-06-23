# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Core Data Containers Integration' do
  let(:test_data) do
    {
      question_input: "What is 2 + 2?",
      context_input: "Basic arithmetic",
      answer_output: "4",
      confidence_output: 0.95
    }
  end

  describe 'Example and Prediction interoperability' do
    it 'creates Examples and converts them to Predictions seamlessly' do
      example = Desiru::Core::Example.new(**test_data)

      expect(example.inputs).to include(question: "What is 2 + 2?", context: "Basic arithmetic")
      expect(example.labels).to include(answer: "4", confidence: 0.95)

      prediction = Desiru::Core::Prediction.new(example)

      expect(prediction.example).to eq(example)
      expect(prediction[:question]).to eq("What is 2 + 2?")
      expect(prediction[:answer]).to eq("4")
    end

    it 'supports round-trip conversion between Example and Prediction' do
      original_example = Desiru::Core::Example.new(**test_data)

      prediction = Desiru::Core::Prediction.new(original_example)
      prediction[:reasoning] = "Simple addition"
      prediction.set_metadata(:model, 'test-model')

      converted_example = prediction.to_example

      expect(converted_example.to_h).to include(original_example.to_h)
      expect(converted_example[:reasoning]).to eq("Simple addition")
      expect(prediction.metadata[:model]).to eq('test-model')
    end

    it 'handles dynamic field access consistently' do
      example = Desiru::Core::Example.new(
        text: "Hello world",
        label: "greeting"
      )

      prediction = Desiru::Core::Prediction.new(example, prediction: "greeting")

      expect(example.text).to eq("Hello world")
      expect(example[:label]).to eq("greeting")
      expect(prediction.text).to eq("Hello world")
      expect(prediction[:prediction]).to eq("greeting")

      example.confidence = 0.8
      prediction.score = 0.9

      expect(example.confidence).to eq(0.8)
      expect(prediction.score).to eq(0.9)
    end

    it 'maintains data integrity across modifications' do
      example = Desiru::Core::Example.new(input: "test", output: "result")
      prediction = Desiru::Core::Prediction.new(example)

      prediction[:output] = "modified_result"

      expect(example[:output]).to eq("result")
      expect(prediction[:output]).to eq("modified_result")
      expect(prediction.example[:output]).to eq("result")
    end
  end

  describe 'Complex data structure handling' do
    let(:complex_data) do
      {
        document_input: {
          title: "Test Document",
          content: ["paragraph 1", "paragraph 2"],
          metadata: { source: "test", date: "2024-01-01" }
        },
        entities_output: [
          { name: "Entity 1", type: "PERSON", confidence: 0.9 },
          { name: "Entity 2", type: "ORG", confidence: 0.8 }
        ],
        summary_output: "This is a test document with entities."
      }
    end

    it 'preserves nested data structures in Examples' do
      example = Desiru::Core::Example.new(**complex_data)

      expect(example.inputs[:document]).to be_a(Hash)
      expect(example.inputs[:document][:content]).to eq(["paragraph 1", "paragraph 2"])
      expect(example.labels[:entities]).to be_an(Array)
      expect(example.labels[:entities].first[:name]).to eq("Entity 1")
    end

    it 'handles nested structures in Predictions' do
      example = Desiru::Core::Example.new(**complex_data)
      prediction = Desiru::Core::Prediction.new(example)

      prediction[:extracted_entities] = [
        { name: "New Entity", type: "LOCATION", confidence: 0.7 }
      ]

      expect(prediction[:extracted_entities]).to be_an(Array)
      expect(prediction[:extracted_entities].first[:confidence]).to eq(0.7)
      expect(prediction[:document][:title]).to eq("Test Document")
    end

    it 'serializes and deserializes complex data correctly' do
      example = Desiru::Core::Example.new(**complex_data)
      serialized = example.to_h
      recreated = Desiru::Core::Example.new(**serialized)

      expect(recreated).to eq(example)
      expect(recreated.inputs[:document][:metadata][:source]).to eq("test")
    end
  end

  describe 'Edge cases and error handling' do
    it 'handles empty Examples gracefully' do
      empty_example = Desiru::Core::Example.new

      expect(empty_example.inputs).to be_empty
      expect(empty_example.labels).to be_empty
      expect(empty_example.keys).to be_empty
    end

    it 'handles nil values in data structures' do
      example = Desiru::Core::Example.new(
        valid_field: "value",
        nil_field: nil,
        empty_array: [],
        empty_hash: {}
      )

      expect(example[:nil_field]).to be_nil
      expect(example[:empty_array]).to eq([])
      expect(example[:empty_hash]).to eq({})
    end

    it 'maintains type consistency across operations' do
      example = Desiru::Core::Example.new(
        string_field: "text",
        number_field: 42,
        boolean_field: true,
        array_field: [1, 2, 3]
      )

      prediction = Desiru::Core::Prediction.new(example)
      converted_back = prediction.to_example

      expect(converted_back[:string_field]).to be_a(String)
      expect(converted_back[:number_field]).to be_a(Integer)
      expect(converted_back[:boolean_field]).to be_a(TrueClass)
      expect(converted_back[:array_field]).to be_an(Array)
    end

    it 'gracefully handles method_missing edge cases' do
      example = Desiru::Core::Example.new(existing_field: "value")

      expect(example.existing_field).to eq("value")
      expect(example.respond_to?(:existing_field)).to be(true)
      expect(example.respond_to?(:nonexistent_field)).to be(false)

      expect { example.nonexistent_field }.to raise_error(NoMethodError)
    end
  end

  describe 'Performance characteristics' do
    it 'handles large datasets efficiently' do
      large_data = {}
      1000.times { |i| large_data["field_#{i}"] = "value_#{i}" }

      start_time = Time.now
      example = Desiru::Core::Example.new(**large_data)
      prediction = Desiru::Core::Prediction.new(example)
      converted = prediction.to_example
      end_time = Time.now

      expect(end_time - start_time).to be < 1.0
      expect(converted.keys.size).to eq(1000)
      expect(converted["field_999"]).to eq("value_999")
    end

    it 'maintains reasonable memory usage for complex objects' do
      examples = []

      100.times do |i|
        examples << Desiru::Core::Example.new(
          id: i,
          data: Array.new(100) { |j| { index: j, value: "item_#{j}" } }
        )
      end

      predictions = examples.map { |ex| Desiru::Core::Prediction.new(ex) }

      expect(examples.size).to eq(100)
      expect(predictions.size).to eq(100)
      expect(predictions.first[:data].size).to eq(100)
    end
  end

  describe 'Equality and comparison' do
    it 'correctly implements equality for Examples' do
      data = { input: "test", output: "result" }
      example1 = Desiru::Core::Example.new(**data)
      example2 = Desiru::Core::Example.new(**data)
      example3 = Desiru::Core::Example.new(input: "different", output: "result")

      expect(example1).to eq(example2)
      expect(example1).not_to eq(example3)
      expect(example1.hash).to eq(example2.hash) if example1.respond_to?(:hash)
    end

    it 'correctly implements equality for Predictions' do
      example = Desiru::Core::Example.new(input: "test")
      prediction1 = Desiru::Core::Prediction.new(example, output: "result")
      prediction2 = Desiru::Core::Prediction.new(example, output: "result")
      prediction3 = Desiru::Core::Prediction.new(example, output: "different")

      expect(prediction1).to eq(prediction2)
      expect(prediction1).not_to eq(prediction3)
    end

    it 'handles equality with metadata' do
      example = Desiru::Core::Example.new(input: "test")
      prediction1 = Desiru::Core::Prediction.new(example)
      prediction2 = Desiru::Core::Prediction.new(example)

      prediction1.set_metadata(:model, 'gpt-4')
      prediction2.set_metadata(:model, 'gpt-4')

      expect(prediction1).to eq(prediction2)

      prediction2.set_metadata(:model, 'gpt-3.5')
      expect(prediction1).not_to eq(prediction2)
    end
  end
end
