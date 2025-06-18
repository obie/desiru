# frozen_string_literal: true

require 'test_helper'
require 'desiru/persistence'

class Desiru::Persistence::DatabaseTest < Minitest::Test
  def setup
    @test_db_url = 'sqlite::memory:'
  end

  def teardown
    Desiru::Persistence::Database.disconnect
  end

  def test_connect_establishes_database_connection
    connection = Desiru::Persistence::Database.connect(@test_db_url)

    assert_instance_of Sequel::SQLite::Database, connection
    assert_equal connection, Desiru::Persistence::Database.connection
  end

  def test_connect_enables_foreign_keys_for_sqlite
    Desiru::Persistence::Database.connect(@test_db_url)

    result = Desiru::Persistence::Database.connection.fetch("PRAGMA foreign_keys").first
    assert_equal 1, result[:foreign_keys]
  end

  def test_disconnect_closes_connection
    Desiru::Persistence::Database.connect(@test_db_url)
    Desiru::Persistence::Database.disconnect

    assert_nil Desiru::Persistence::Database.connection
  end

  def test_migrate_runs_database_migrations
    Desiru::Persistence::Database.connect(@test_db_url)

    # Should not raise any errors
    Desiru::Persistence::Database.migrate!

    # Check that tables were created
    tables = Desiru::Persistence::Database.connection.tables
    assert_includes tables, :api_requests
    assert_includes tables, :module_executions
    assert_includes tables, :optimization_results
    assert_includes tables, :training_examples
  end

  def test_migrate_raises_error_if_not_connected
    error = assert_raises RuntimeError do
      Desiru::Persistence::Database.migrate!
    end

    assert_equal 'Not connected to database', error.message
  end

  def test_transaction_executes_block
    Desiru::Persistence::Database.connect(@test_db_url)
    Desiru::Persistence::Database.migrate!

    result = Desiru::Persistence::Database.transaction do
      Desiru::Persistence::Database.connection[:api_requests].insert(
        method: 'GET',
        path: '/test',
        status_code: 200,
        created_at: Time.now,
        updated_at: Time.now
      )
      42
    end

    assert_equal 42, result
    assert_equal 1, Desiru::Persistence::Database.connection[:api_requests].count
  end

  def test_transaction_rolls_back_on_error
    Desiru::Persistence::Database.connect(@test_db_url)
    Desiru::Persistence::Database.migrate!

    assert_raises RuntimeError do
      Desiru::Persistence::Database.transaction do
        Desiru::Persistence::Database.connection[:api_requests].insert(
          method: 'GET',
          path: '/test',
          status_code: 200,
          created_at: Time.now,
          updated_at: Time.now
        )
        raise 'Error!'
      end
    end

    assert_equal 0, Desiru::Persistence::Database.connection[:api_requests].count
  end
end
