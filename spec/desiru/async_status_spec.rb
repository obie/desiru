# frozen_string_literal: true

require 'spec_helper'
require 'desiru/async_capable'

RSpec.describe 'Async Status Tracking' do
  let(:redis) { instance_double(Redis) }
  let(:job_id) { 'test-job-123' }
  let(:async_result) { Desiru::AsyncResult.new(job_id) }

  before do
    allow(Redis).to receive(:new).and_return(redis)
  end

  describe 'AsyncResult#status' do
    context 'when status data exists' do
      let(:status_data) do
        {
          status: 'running',
          progress: 50,
          message: 'Processing...',
          updated_at: Time.now.iso8601
        }
      end

      before do
        allow(redis).to receive(:get).with("desiru:status:#{job_id}")
          .and_return(status_data.to_json)
      end

      it 'returns the current status' do
        expect(async_result.status).to eq('running')
      end
    end

    context 'when status data does not exist' do
      before do
        allow(redis).to receive(:get).with("desiru:status:#{job_id}")
          .and_return(nil)
      end

      it 'returns pending' do
        expect(async_result.status).to eq('pending')
      end
    end
  end

  describe 'AsyncResult#progress' do
    context 'when progress data exists' do
      let(:status_data) do
        {
          status: 'running',
          progress: 75,
          message: 'Almost done...',
          updated_at: Time.now.iso8601
        }
      end

      before do
        allow(redis).to receive(:get).with("desiru:status:#{job_id}")
          .and_return(status_data.to_json)
      end

      it 'returns the progress percentage' do
        expect(async_result.progress).to eq(75)
      end
    end

    context 'when progress data does not exist' do
      before do
        allow(redis).to receive(:get).with("desiru:status:#{job_id}")
          .and_return(nil)
      end

      it 'returns nil' do
        expect(async_result.progress).to be_nil
      end
    end
  end

  describe 'Job status updates' do
    let(:job) { Desiru::Jobs::AsyncPredict.new }
    let(:module_class_name) { 'Desiru::Predict' }
    let(:signature_str) { 'question -> answer' }
    let(:inputs) { { question: 'What is 2+2?' } }
    let(:options) { {} }
    let(:module_instance) { instance_double(Desiru::Predict) }
    let(:result) { Desiru::ModuleResult.new(answer: '4') }

    before do
      predict_class = class_double(Desiru::Predict)
      stub_const('Desiru::Predict', predict_class)
      allow(predict_class).to receive(:new).and_return(module_instance)
      allow(module_instance).to receive(:call).and_return(result)
    end

    it 'updates status during job execution' do
      # Expect status updates in sequence
      expect(redis).to receive(:setex) do |key, ttl, json_data|
        expect(key).to eq("desiru:status:#{job_id}")
        expect(ttl).to eq(86_400)
        data = JSON.parse(json_data, symbolize_names: true)
        expect(data[:status]).to eq('running')
        expect(data[:message]).to eq('Initializing module')
      end.ordered

      expect(redis).to receive(:setex) do |key, ttl, json_data|
        expect(key).to eq("desiru:status:#{job_id}")
        expect(ttl).to eq(86_400)
        data = JSON.parse(json_data, symbolize_names: true)
        expect(data[:status]).to eq('running')
        expect(data[:progress]).to eq(50)
        expect(data[:message]).to eq('Processing request')
      end.ordered

      expect(redis).to receive(:setex) do |key, ttl, json_data|
        expect(key).to eq("desiru:status:#{job_id}")
        expect(ttl).to eq(86_400)
        data = JSON.parse(json_data, symbolize_names: true)
        expect(data[:status]).to eq('completed')
        expect(data[:progress]).to eq(100)
        expect(data[:message]).to eq('Request completed successfully')
      end.ordered

      # Expect result storage
      allow(redis).to receive(:setex).with(
        "desiru:results:#{job_id}",
        3600,
        anything
      )

      job.perform(job_id, module_class_name, signature_str, inputs, options)
    end

    context 'when job fails' do
      let(:error) { StandardError.new('Processing failed') }

      before do
        allow(module_instance).to receive(:call).and_raise(error)
      end

      it 'updates status to failed' do
        # Allow initial status updates
        allow(redis).to receive(:setex).with(
          "desiru:status:#{job_id}",
          86_400,
          anything
        )

        # Expect failed status
        expect(redis).to receive(:setex) do |key, ttl, json_data|
          data = JSON.parse(json_data, symbolize_names: true)
          if data[:status] == 'failed'
            expect(key).to eq("desiru:status:#{job_id}")
            expect(ttl).to eq(86_400)
            expect(data[:message]).to eq('Error: Processing failed')
          end
        end.at_least(:once)

        # Expect error result storage
        allow(redis).to receive(:setex).with(
          "desiru:results:#{job_id}",
          3600,
          anything
        )

        expect { job.perform(job_id, module_class_name, signature_str, inputs, options) }
          .to raise_error(StandardError, 'Processing failed')
      end
    end
  end
end