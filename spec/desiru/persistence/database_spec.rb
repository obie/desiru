# frozen_string_literal: true

require 'spec_helper'
require 'desiru/persistence'

RSpec.describe Desiru::Persistence::Database, :persistence do
  let(:test_db_url) { 'sqlite::memory:' }

  describe '.connect' do
    it 'establishes a database connection' do
      connection = described_class.connect(test_db_url)
      expect(connection).to be_a(Sequel::Database)
      expect(described_class.connection).to eq(connection)
    end

    it 'enables foreign keys for SQLite' do
      described_class.connect(test_db_url)
      result = described_class.connection.fetch("PRAGMA foreign_keys").first
      expect(result[:foreign_keys]).to eq(1)
    end

    it 'uses the default database URL if none provided' do
      allow(Desiru::Persistence).to receive(:database_url).and_return(test_db_url)
      connection = described_class.connect
      expect(connection).to be_a(Sequel::Database)
    end
  end

  describe '.disconnect' do
    it 'closes the database connection' do
      described_class.connect(test_db_url)
      described_class.disconnect
      expect(described_class.connection).to be_nil
    end
  end

  describe '.migrate!' do
    before do
      described_class.connect(test_db_url)
    end

    it 'runs database migrations' do
      expect { described_class.migrate! }.not_to raise_error

      # Check that tables were created
      tables = described_class.connection.tables
      expect(tables).to include(:api_requests)
      expect(tables).to include(:module_executions)
      expect(tables).to include(:optimization_results)
      expect(tables).to include(:training_examples)
    end

    it 'raises an error if not connected' do
      described_class.disconnect
      expect { described_class.migrate! }.to raise_error('Not connected to database')
    end
  end

  describe '.transaction' do
    before do
      described_class.connect(test_db_url)
      described_class.migrate!
    end

    it 'executes a block within a transaction' do
      result = described_class.transaction do
        described_class.connection[:api_requests].insert(
          method: 'GET',
          path: '/test',
          status_code: 200,
          created_at: Time.now,
          updated_at: Time.now
        )
        42
      end

      expect(result).to eq(42)
      expect(described_class.connection[:api_requests].count).to eq(1)
    end

    it 'rolls back on error' do
      expect do
        described_class.transaction do
          described_class.connection[:api_requests].insert(
            method: 'GET',
            path: '/test',
            status_code: 200,
            created_at: Time.now,
            updated_at: Time.now
          )
          raise 'Error!'
        end
      end.to raise_error('Error!')

      expect(described_class.connection[:api_requests].count).to eq(0)
    end

    it 'raises an error if not connected' do
      described_class.disconnect
      expect { described_class.transaction { 1 + 1 } }.to raise_error('Not connected to database')
    end
  end
end
