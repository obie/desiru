# frozen_string_literal: true

require 'spec_helper'
require 'desiru/async_capable'
require 'desiru/async_status'

RSpec.describe 'Async Status' do
  describe Desiru::AsyncResult do
    let(:redis) { instance_double(Redis) }
    let(:job_id) { 'test-job-123' }
    let(:async_result) { described_class.new(job_id) }

    before do
      allow(Redis).to receive(:new).and_return(redis)
    end

    describe '#status' do
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

    describe '#progress' do
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
  end

  describe Desiru::AsyncStatus do
    let(:job_id) { 'test-job-456' }
    let(:async_status) { described_class.new(job_id) }
    let(:redis) { instance_double(Redis) }

    before do
      allow(Redis).to receive(:new).and_return(redis)
    end

    describe '#initialize' do
      it 'stores the job_id' do
        expect(async_status.job_id).to eq(job_id)
      end
    end

    describe '#status' do
      context 'when status exists in Redis' do
        it 'returns the status from Redis' do
          status_data = { status: 'processing', progress: 50 }.to_json
          allow(redis).to receive(:get).with("desiru:status:#{job_id}").and_return(status_data)

          expect(async_status.status).to eq('processing')
        end
      end

      context 'when status does not exist' do
        it 'returns pending' do
          allow(redis).to receive(:get).with("desiru:status:#{job_id}").and_return(nil)

          expect(async_status.status).to eq('pending')
        end
      end

      context 'when status data has no status field' do
        it 'returns pending' do
          status_data = { progress: 50 }.to_json
          allow(redis).to receive(:get).with("desiru:status:#{job_id}").and_return(status_data)

          expect(async_status.status).to eq('pending')
        end
      end
    end

    describe '#progress' do
      context 'when status exists with progress' do
        it 'returns the progress value' do
          status_data = { status: 'processing', progress: 75 }.to_json
          allow(redis).to receive(:get).with("desiru:status:#{job_id}").and_return(status_data)

          expect(async_status.progress).to eq(75)
        end
      end

      context 'when status does not exist' do
        it 'returns 0' do
          allow(redis).to receive(:get).with("desiru:status:#{job_id}").and_return(nil)

          expect(async_status.progress).to eq(0)
        end
      end

      context 'when status has no progress field' do
        it 'returns 0' do
          status_data = { status: 'processing' }.to_json
          allow(redis).to receive(:get).with("desiru:status:#{job_id}").and_return(status_data)

          expect(async_status.progress).to eq(0)
        end
      end
    end

    describe '#ready?' do
      context 'when result exists' do
        it 'returns true' do
          result_data = { success: true, result: { answer: 'test' } }.to_json
          allow(redis).to receive(:get).with("desiru:results:#{job_id}").and_return(result_data)

          expect(async_status.ready?).to be true
        end
      end

      context 'when result does not exist' do
        it 'returns false' do
          allow(redis).to receive(:get).with("desiru:results:#{job_id}").and_return(nil)

          expect(async_status.ready?).to be false
        end
      end
    end

    describe '#result' do
      context 'when job succeeded' do
        it 'returns the result' do
          result_data = { success: true, result: { answer: 'test answer' } }.to_json
          allow(redis).to receive(:get).with("desiru:results:#{job_id}").and_return(result_data)

          expect(async_status.result).to eq({ answer: 'test answer' })
        end
      end

      context 'when job failed' do
        it 'raises ModuleError' do
          result_data = { success: false, error: 'Job failed' }.to_json
          allow(redis).to receive(:get).with("desiru:results:#{job_id}").and_return(result_data)

          expect { async_status.result }.to raise_error(Desiru::ModuleError, 'Async job failed: Job failed')
        end
      end

      context 'when result does not exist' do
        it 'returns nil' do
          allow(redis).to receive(:get).with("desiru:results:#{job_id}").and_return(nil)

          expect(async_status.result).to be_nil
        end
      end
    end

    describe 'error handling' do
      context 'when Redis returns invalid JSON' do
        it 'handles JSON parse errors gracefully for status' do
          allow(redis).to receive(:get).with("desiru:status:#{job_id}").and_return('invalid json')

          expect(async_status.status).to eq('pending')
        end

        it 'handles JSON parse errors gracefully for result' do
          allow(redis).to receive(:get).with("desiru:results:#{job_id}").and_return('invalid json')

          expect(async_status.ready?).to be false
        end
      end
    end
  end
end
