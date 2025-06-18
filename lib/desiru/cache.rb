# frozen_string_literal: true

module Desiru
  # Thread-safe in-memory cache with TTL support and LRU eviction
  class Cache
    Entry = Struct.new(:value, :expires_at, :accessed_at, keyword_init: true)

    def initialize(max_size: 1000, cleanup_interval: 300)
      @store = {}
      @mutex = Mutex.new
      @max_size = max_size
      @cleanup_interval = cleanup_interval
      @last_cleanup = Time.now
    end

    # Get a value from cache or set it using the provided block
    def get_or_set(key, ttl: 3600)
      @mutex.synchronize do
        cleanup_if_needed

        if (entry = @store[key])
          if entry.expires_at > Time.now
            entry.accessed_at = Time.now
            return entry.value
          else
            @store.delete(key)
          end
        end

        # Evict LRU if at capacity
        evict_lru if @store.size >= @max_size

        value = yield
        @store[key] = Entry.new(
          value: value,
          expires_at: Time.now + ttl,
          accessed_at: Time.now
        )
        value
      end
    end

    # Get a value from cache without setting
    def get(key)
      @mutex.synchronize do
        if (entry = @store[key])
          if entry.expires_at > Time.now
            entry.accessed_at = Time.now
            entry.value
          else
            @store.delete(key)
            nil
          end
        end
      end
    end

    # Set a value in cache
    def set(key, value, ttl: 3600)
      @mutex.synchronize do
        cleanup_if_needed
        evict_lru if @store.size >= @max_size && !@store.key?(key)

        @store[key] = Entry.new(
          value: value,
          expires_at: Time.now + ttl,
          accessed_at: Time.now
        )
        value
      end
    end

    # Delete a key from cache
    def delete(key)
      @mutex.synchronize do
        @store.delete(key)
      end
    end

    # Clear all entries
    def clear
      @mutex.synchronize do
        @store.clear
      end
    end

    # Get the current size
    def size
      @mutex.synchronize do
        @store.size
      end
    end

    # Manually trigger cleanup of expired entries
    def cleanup_expired
      @mutex.synchronize do
        @store.delete_if { |_, entry| entry.expires_at <= Time.now }
      end
    end

    private

    def cleanup_if_needed
      return unless Time.now - @last_cleanup > @cleanup_interval

      @store.delete_if { |_, entry| entry.expires_at <= Time.now }
      @last_cleanup = Time.now
    end

    def evict_lru
      # Find least recently used entry
      lru_key = @store.min_by { |_, entry| entry.accessed_at }&.first
      @store.delete(lru_key) if lru_key
    end
  end
end