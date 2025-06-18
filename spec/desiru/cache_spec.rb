# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Desiru::Cache do
  let(:cache) { described_class.new }

  describe '#get_or_set' do
    it 'stores and retrieves values' do
      result = cache.get_or_set('key1') { 'value1' }
      expect(result).to eq('value1')
      
      # Should return cached value without calling block
      result = cache.get_or_set('key1') { 'value2' }
      expect(result).to eq('value1')
    end

    it 'respects TTL' do
      cache.get_or_set('key1', ttl: 0.1) { 'value1' }
      expect(cache.get('key1')).to eq('value1')
      
      sleep 0.2
      expect(cache.get('key1')).to be_nil
      
      # Should call block again after expiry
      result = cache.get_or_set('key1', ttl: 1) { 'value2' }
      expect(result).to eq('value2')
    end

    it 'is thread-safe' do
      results = []
      threads = []
      
      10.times do |i|
        threads << Thread.new do
          result = cache.get_or_set("key#{i % 3}") do
            sleep 0.01 # Simulate some work
            "value#{i}"
          end
          results << result
        end
      end
      
      threads.each(&:join)
      expect(results.size).to eq(10)
      expect(results.uniq.size).to be <= 3 # At most 3 unique values
    end
  end

  describe '#get' do
    it 'returns nil for missing keys' do
      expect(cache.get('missing')).to be_nil
    end

    it 'returns stored values' do
      cache.set('key1', 'value1')
      expect(cache.get('key1')).to eq('value1')
    end

    it 'returns nil for expired values' do
      cache.set('key1', 'value1', ttl: 0.1)
      sleep 0.2
      expect(cache.get('key1')).to be_nil
    end
  end

  describe '#set' do
    it 'stores values' do
      cache.set('key1', 'value1')
      expect(cache.get('key1')).to eq('value1')
    end

    it 'overwrites existing values' do
      cache.set('key1', 'value1')
      cache.set('key1', 'value2')
      expect(cache.get('key1')).to eq('value2')
    end
  end

  describe '#delete' do
    it 'removes keys from cache' do
      cache.set('key1', 'value1')
      cache.delete('key1')
      expect(cache.get('key1')).to be_nil
    end

    it 'handles missing keys gracefully' do
      expect { cache.delete('missing') }.not_to raise_error
    end
  end

  describe '#clear' do
    it 'removes all entries' do
      cache.set('key1', 'value1')
      cache.set('key2', 'value2')
      cache.clear
      
      expect(cache.get('key1')).to be_nil
      expect(cache.get('key2')).to be_nil
      expect(cache.size).to eq(0)
    end
  end

  describe '#size' do
    it 'returns the number of entries' do
      expect(cache.size).to eq(0)
      
      cache.set('key1', 'value1')
      expect(cache.size).to eq(1)
      
      cache.set('key2', 'value2')
      expect(cache.size).to eq(2)
      
      cache.delete('key1')
      expect(cache.size).to eq(1)
    end
  end

  describe 'LRU eviction' do
    let(:small_cache) { described_class.new(max_size: 3) }

    it 'evicts least recently used entries when at capacity' do
      small_cache.set('key1', 'value1')
      small_cache.set('key2', 'value2')
      small_cache.set('key3', 'value3')
      
      # Access key1 to make it more recently used
      small_cache.get('key1')
      
      # Adding key4 should evict key2 (least recently used)
      small_cache.set('key4', 'value4')
      
      expect(small_cache.get('key1')).to eq('value1')
      expect(small_cache.get('key2')).to be_nil
      expect(small_cache.get('key3')).to eq('value3')
      expect(small_cache.get('key4')).to eq('value4')
    end

    it 'updates access time on get' do
      small_cache.set('key1', 'value1')
      small_cache.set('key2', 'value2')
      small_cache.set('key3', 'value3')
      
      # Access keys in order: key2, key3, key1
      small_cache.get('key2')
      sleep 0.01
      small_cache.get('key3')
      sleep 0.01
      small_cache.get('key1')
      
      # key2 should be evicted as least recently used
      small_cache.set('key4', 'value4')
      
      expect(small_cache.get('key1')).to eq('value1')
      expect(small_cache.get('key2')).to be_nil
      expect(small_cache.get('key3')).to eq('value3')
      expect(small_cache.get('key4')).to eq('value4')
    end
  end

  describe '#cleanup_expired' do
    it 'removes expired entries' do
      cache.set('key1', 'value1', ttl: 0.1)
      cache.set('key2', 'value2', ttl: 10)
      
      sleep 0.2
      cache.cleanup_expired
      
      expect(cache.get('key1')).to be_nil
      expect(cache.get('key2')).to eq('value2')
      expect(cache.size).to eq(1)
    end
  end

  describe 'automatic cleanup' do
    let(:cache_with_cleanup) { described_class.new(cleanup_interval: 0.1) }

    it 'automatically cleans up expired entries' do
      cache_with_cleanup.set('key1', 'value1', ttl: 0.05)
      cache_with_cleanup.set('key2', 'value2', ttl: 10)
      
      sleep 0.15
      
      # Trigger cleanup by setting a new value
      cache_with_cleanup.set('key3', 'value3')
      
      expect(cache_with_cleanup.size).to eq(2) # key1 should be cleaned up
      expect(cache_with_cleanup.get('key1')).to be_nil
      expect(cache_with_cleanup.get('key2')).to eq('value2')
    end
  end

  describe 'edge cases' do
    it 'handles nil values' do
      cache.set('key1', nil)
      expect(cache.get('key1')).to be_nil
      expect(cache.size).to eq(1)
    end

    it 'handles complex objects' do
      obj = { name: 'test', data: [1, 2, 3] }
      cache.set('key1', obj)
      expect(cache.get('key1')).to eq(obj)
    end

    it 'handles concurrent access to same key' do
      counter = 0
      threads = []
      
      10.times do
        threads << Thread.new do
          cache.get_or_set('shared_key') do
            counter += 1
            sleep 0.01
            'shared_value'
          end
        end
      end
      
      threads.each(&:join)
      
      # Block should only be called once
      expect(counter).to eq(1)
      expect(cache.get('shared_key')).to eq('shared_value')
    end
  end
end