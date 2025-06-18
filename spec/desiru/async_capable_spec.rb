# frozen_string_literal: true

require 'spec_helper'
require 'desiru/async_capable'

RSpec.describe Desiru::AsyncCapable do
  let(:test_class) do
    Class.new do
      include Desiru::AsyncCapable

      attr_reader :signature, :model, :config, :demos

      def initialize(model)
        @signature = Desiru::Signature.new('question -> answer')
        @model = model
        @config = { temperature: 0.7 }
        @demos = []
      end
    end
  end

  let(:model) { double('model', class: double(name: 'TestModel'), to_config: { api_key: 'test' }) }
  let(:instance) { test_class.new(model) }

  describe '#call_async' do
    let(:job_id) { 'uuid-123' }

    before do
      allow(SecureRandom).to receive(:uuid).and_return(job_id)
      allow(Desiru::Jobs::AsyncPredict).to receive(:perform_async)
    end

    it 'enqueues an async job with the correct parameters' do
      expect(Desiru::Jobs::AsyncPredict).to receive(:perform_async).with(
        job_id,
        test_class.name,
        'question -> answer',
        { question: 'What is 2+2?' },
        hash_including(
          'model_class' => 'TestModel',
          'model_config' => { api_key: 'test' },
          'config' => { temperature: 0.7 },
          'demos' => []
        )
      )

      result = instance.call_async(question: 'What is 2+2?')
      expect(result).to be_a(Desiru::AsyncResult)
      expect(result.job_id).to eq(job_id)
    end
  end

  describe '#call_batch_async' do
    let(:batch_id) { 'batch-uuid-456' }
    let(:inputs_array) do
      [
        { question: 'What is 2+2?' },
        { question: 'What is 3+3?' }
      ]
    end

    before do
      allow(SecureRandom).to receive(:uuid).and_return(batch_id)
      allow(Desiru::Jobs::BatchProcessor).to receive(:perform_async)
    end

    it 'enqueues a batch job with the correct parameters' do
      expect(Desiru::Jobs::BatchProcessor).to receive(:perform_async).with(
        batch_id,
        test_class.name,
        'question -> answer',
        inputs_array,
        hash_including(
          'model_class' => 'TestModel',
          'model_config' => { api_key: 'test' },
          'config' => { temperature: 0.7 },
          'demos' => []
        )
      )

      result = instance.call_batch_async(inputs_array)
      expect(result).to be_a(Desiru::BatchResult)
      expect(result.job_id).to eq(batch_id)
    end
  end
end

RSpec.describe Desiru::AsyncResult do
  let(:job_id) { 'test-job-123' }
  let(:async_result) { described_class.new(job_id) }
  let(:redis) { instance_double(Redis) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
  end

  describe '#ready?' do
    context 'when result exists' do
      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return({ success: true, result: { answer: '4' } }.to_json)
      end

      it 'returns true' do
        expect(async_result.ready?).to be true
      end
    end

    context 'when result does not exist' do
      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return(nil)
      end

      it 'returns false' do
        expect(async_result.ready?).to be false
      end
    end
  end

  describe '#success?' do
    context 'when job succeeded' do
      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return({ success: true, result: { answer: '4' } }.to_json)
      end

      it 'returns true' do
        expect(async_result.success?).to be true
      end
    end

    context 'when job failed' do
      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return({ success: false, error: 'Failed' }.to_json)
      end

      it 'returns false' do
        expect(async_result.success?).to be false
      end
    end
  end

  describe '#result' do
    context 'when job succeeded' do
      let(:result_data) { { answer: '4' } }

      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return({ success: true, result: result_data }.to_json)
      end

      it 'returns a ModuleResult' do
        result = async_result.result
        expect(result).to be_a(Desiru::ModuleResult)
        expect(result.answer).to eq('4')
      end
    end

    context 'when job failed' do
      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return({ success: false, error: 'Model error' }.to_json)
      end

      it 'raises an error' do
        expect { async_result.result }
          .to raise_error(Desiru::ModuleError, /Async job failed: Model error/)
      end
    end
  end

  describe '#wait' do
    context 'when result becomes ready' do
      before do
        call_count = 0
        allow(redis).to receive(:get).with("desiru:results:#{job_id}") do
          call_count += 1
          if call_count < 3
            nil
          else
            { success: true, result: { answer: '4' } }.to_json
          end
        end
      end

      it 'polls until result is ready' do
        result = async_result.wait(timeout: 2, poll_interval: 0.1)
        expect(result).to be_a(Desiru::ModuleResult)
        expect(result.answer).to eq('4')
      end
    end

    context 'when timeout is exceeded' do
      before do
        allow(redis).to receive(:get).with("desiru:results:#{job_id}")
                                     .and_return(nil)
      end

      it 'raises TimeoutError' do
        expect { async_result.wait(timeout: 0.1, poll_interval: 0.05) }
          .to raise_error(Desiru::TimeoutError, /not ready after/)
      end
    end
  end
end
