# frozen_string_literal: true

require 'spec_helper'
require 'desiru/graphql/schema_generator'

RSpec.describe Desiru::GraphQL::SchemaGenerator do
  subject(:generator) { described_class.new }

  describe '#register_signature' do
    it 'registers a signature with a name' do
      signature = Desiru::Signature.new('question: string -> answer: string')
      generator.register_signature('askQuestion', signature)

      expect(generator.signatures['askQuestion']).to eq(signature)
    end
  end

  describe '#generate_schema' do
    context 'with simple signature' do
      before do
        signature = Desiru::Signature.new('question: string -> answer: string')
        generator.register_signature('askQuestion', signature)
      end

      it 'generates a GraphQL schema' do
        schema = generator.generate_schema

        expect(schema.ancestors).to include(GraphQL::Schema)
        expect(schema.query).not_to be_nil
      end

      it 'creates query field for signature' do
        schema = generator.generate_schema
        query_type = schema.query

        expect(query_type.fields).to have_key('askQuestion')
      end

      it 'adds input arguments' do
        schema = generator.generate_schema
        field = schema.query.fields['askQuestion']

        expect(field.arguments).to have_key('question')
        expect(field.arguments['question'].type).to be_non_null
        expect(field.arguments['question'].type.unwrap).to eq(GraphQL::Types::String)
      end

      it 'creates output type' do
        schema = generator.generate_schema
        field = schema.query.fields['askQuestion']
        output_type = field.type.unwrap

        expect(output_type.ancestors).to include(GraphQL::Schema::Object)
        expect(output_type.fields).to have_key('answer')
      end
    end

    context 'with typed signature' do
      before do
        signature = Desiru::Signature.new(
          'text: string, max_length: int -> summary: string, word_count: int'
        )
        generator.register_signature('summarize', signature)
      end

      it 'handles multiple input fields' do
        schema = generator.generate_schema
        field = schema.query.fields['summarize']

        expect(field.arguments).to have_key('text')
        expect(field.arguments).to have_key('maxLength')
        expect(field.arguments['maxLength'].type).to be_non_null
        expect(field.arguments['maxLength'].type.unwrap).to eq(GraphQL::Types::Int)
      end

      it 'handles multiple output fields' do
        schema = generator.generate_schema
        field = schema.query.fields['summarize']
        output_type = field.type.unwrap

        expect(output_type.fields).to have_key('summary')
        expect(output_type.fields).to have_key('wordCount')
      end
    end

    context 'with optional fields' do
      before do
        signature = Desiru::Signature.new('question: string, context?: string -> answer: string')
        generator.register_signature('askWithContext', signature)
      end

      it 'makes optional fields nullable' do
        schema = generator.generate_schema
        field = schema.query.fields['askWithContext']

        expect(field.arguments['question'].type).to be_non_null
        expect(field.arguments['question'].type.unwrap).to eq(GraphQL::Types::String)
        expect(field.arguments['context'].type).to eq(GraphQL::Types::String)
      end
    end

    context 'with literal types' do
      before do
        signature = Desiru::Signature.new(
          "sentiment: Literal['positive', 'negative', 'neutral'] -> score: float"
        )
        generator.register_signature('analyzeSentiment', signature)
      end

      it 'creates enum type for literals' do
        schema = generator.generate_schema
        field = schema.query.fields['analyzeSentiment']
        sentiment_arg = field.arguments['sentiment']

        expect(sentiment_arg.type.unwrap.ancestors).to include(GraphQL::Schema::Enum)
      end
    end

    context 'with list types' do
      before do
        signature = Desiru::Signature.new('queries: list[string] -> responses: list[string]')
        generator.register_signature('batchQuery', signature)
      end

      it 'creates list types' do
        schema = generator.generate_schema
        field = schema.query.fields['batchQuery']

        # Check that queries argument is a non-null list
        queries_type = field.arguments['queries'].type
        expect(queries_type).to be_non_null
        expect(queries_type.of_type).to be_a(GraphQL::Schema::List)

        output_type = field.type.unwrap
        # Check that responses field is a non-null list
        responses_type = output_type.fields['responses'].type
        expect(responses_type).to be_non_null
        expect(responses_type.of_type).to be_a(GraphQL::Schema::List)
      end
    end

    context 'with multiple signatures' do
      before do
        generator.register_signature(
          'ask',
          Desiru::Signature.new('question: string -> answer: string')
        )
        generator.register_signature(
          'translate',
          Desiru::Signature.new('text: string, target_lang: string -> translation: string')
        )
      end

      it 'creates multiple query fields' do
        schema = generator.generate_schema

        expect(schema.query.fields).to have_key('ask')
        expect(schema.query.fields).to have_key('translate')
      end
    end
  end

  describe 'schema execution' do
    it 'generates executable GraphQL schema' do
      # Set up a mock model for testing
      mock_model = double('model')
      allow(Desiru.configuration).to receive(:default_model).and_return(mock_model)

      signature = Desiru::Signature.new('name: string -> greeting: string')
      generator.register_signature('greet', signature)

      schema = generator.generate_schema

      # Verify the schema has the expected structure
      expect(schema).to respond_to(:execute)
      expect(schema.query).not_to be_nil
      expect(schema.query.fields).to have_key('greet')
    end
  end
end
