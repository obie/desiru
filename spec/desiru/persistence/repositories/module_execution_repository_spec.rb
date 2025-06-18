# frozen_string_literal: true

require 'spec_helper'
require 'desiru/persistence'

RSpec.describe Desiru::Persistence::Repositories::ModuleExecutionRepository do
  let(:repository) { Desiru::Persistence[:module_executions] }
  
  before(:all) do
    Desiru::Persistence::Database.connect('sqlite::memory:')
    Desiru::Persistence::Database.migrate!
  end
  
  after(:all) do
    Desiru::Persistence::Database.disconnect
  end
  
  before(:each) do
    # Clear all data before each test
    Desiru::Persistence::Database.connection[:module_executions].delete
    Desiru::Persistence::Database.connection[:api_requests].delete
  end
  
  describe '#create_for_module' do
    it 'creates a new module execution record' do
      execution = repository.create_for_module('TestModule', { input: 'test' })
      
      expect(execution).to be_a(Desiru::Persistence::Models::ModuleExecution)
      expect(execution.module_name).to eq('TestModule')
      expect(execution.inputs).to eq({ 'input' => 'test' })
      expect(execution.status).to eq('pending')
      expect(execution.started_at).to be_within(1).of(Time.now)
    end
    
    it 'associates with an API request if provided' do
      # Create an API request first
      api_request = Desiru::Persistence::Database.connection[:api_requests].insert(
        method: 'POST',
        path: '/test',
        status_code: 200,
        created_at: Time.now,
        updated_at: Time.now
      )
      
      execution = repository.create_for_module('TestModule', { input: 'test' }, 
                                               api_request_id: api_request)
      
      expect(execution.api_request_id).to eq(api_request)
    end
  end
  
  describe '#complete' do
    let(:execution) { repository.create_for_module('TestModule', { input: 'test' }) }
    
    it 'marks an execution as completed with outputs' do
      updated = repository.complete(execution.id, { output: 'result' }, { timing: 1.5 })
      
      expect(updated.status).to eq('completed')
      expect(updated.outputs).to eq({ 'output' => 'result' })
      expect(updated.metadata).to eq({ 'timing' => 1.5 })
      expect(updated.finished_at).to be_within(1).of(Time.now)
    end
  end
  
  describe '#fail' do
    let(:execution) { repository.create_for_module('TestModule', { input: 'test' }) }
    
    it 'marks an execution as failed with error details' do
      updated = repository.fail(execution.id, 'Something went wrong', 'backtrace here')
      
      expect(updated.status).to eq('failed')
      expect(updated.error_message).to eq('Something went wrong')
      expect(updated.error_backtrace).to eq('backtrace here')
      expect(updated.finished_at).to be_within(1).of(Time.now)
    end
  end
  
  describe '#find_by_module' do
    before do
      repository.create_for_module('ModuleA', { input: 'a' })
      repository.create_for_module('ModuleB', { input: 'b' })
      repository.create_for_module('ModuleA', { input: 'a2' })
    end
    
    it 'returns all executions for a specific module' do
      results = repository.find_by_module('ModuleA')
      
      expect(results.length).to eq(2)
      expect(results.all? { |r| r.module_name == 'ModuleA' }).to be true
    end
  end
  
  describe '#success_rate' do
    before do
      # Create some executions with different statuses
      3.times { repository.complete(repository.create_for_module('TestModule', {}).id, {}) }
      2.times { repository.fail(repository.create_for_module('TestModule', {}).id, 'error') }
      repository.create_for_module('TestModule', {}) # pending
    end
    
    it 'calculates the success rate for all modules' do
      rate = repository.success_rate
      expect(rate).to eq(50.0) # 3 completed out of 6 total
    end
    
    it 'calculates the success rate for a specific module' do
      # Add some other module executions
      repository.complete(repository.create_for_module('OtherModule', {}).id, {})
      
      rate = repository.success_rate('TestModule')
      expect(rate).to eq(50.0) # Still 3 out of 6 for TestModule
    end
  end
  
  describe '#average_duration' do
    before do
      # Create completed executions with known durations
      execution1 = repository.create_for_module('TestModule', {})
      sleep 0.1
      repository.complete(execution1.id, {})
      
      execution2 = repository.create_for_module('TestModule', {})
      sleep 0.2
      repository.complete(execution2.id, {})
    end
    
    it 'calculates the average duration for completed executions' do
      duration = repository.average_duration
      expect(duration).to be > 0
      expect(duration).to be < 1 # Should be less than 1 second
    end
    
    it 'returns nil if no completed executions' do
      # Clear existing data
      Desiru::Persistence::Database.connection[:module_executions].delete
      
      expect(repository.average_duration).to be_nil
    end
  end
  
  describe '#recent' do
    before do
      5.times do |i|
        execution = repository.create_for_module("Module#{i}", {})
        # Update started_at to ensure ordering
        Desiru::Persistence::Database.connection[:module_executions]
          .where(id: execution.id)
          .update(started_at: Time.now - (i * 60))
      end
    end
    
    it 'returns the most recent executions' do
      recent = repository.recent(3)
      
      expect(recent.length).to eq(3)
      expect(recent.first.module_name).to eq('Module0')
      expect(recent.last.module_name).to eq('Module2')
    end
  end
end