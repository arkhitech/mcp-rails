require "test_helper"

module MCP
  module Rails
    class BypassKeyManagerTest < ActiveSupport::TestCase
      def setup
        @temp_dir = Dir.mktmpdir
        @key_path = File.join(@temp_dir, "bypass_key.txt")
        MCP::Rails.configure do |config|
          config.bypass_key_path = @key_path
        end
      end

      def teardown
        FileUtils.remove_entry @temp_dir
        MCP::Rails.reset_configuration!
      end

      test "generates a new 32-byte hex key" do
        key = MCP::Rails::BypassKeyManager.generate_key

        assert_equal 64, key.length # 32 bytes = 64 hex characters
        assert_match(/\A[0-9a-f]{64}\z/, key) # Validates hex format
      end

      test "saves and loads bypass key" do
        manager = MCP::Rails::BypassKeyManager
        original_key = manager.generate_key
        manager.save_key(original_key)

        # Verify key was saved
        assert File.exist?(@key_path)

        # Verify key content
        saved_key = File.read(@key_path).strip
        assert_equal original_key, saved_key

        # Verify loading key
        loaded_key = manager.load_key
        assert_equal original_key, loaded_key
      end

      test "generates new key if none exists" do
        manager = MCP::Rails::BypassKeyManager
        key = manager.key

        assert_not_nil key
        assert_equal 64, key.length
        assert File.exist?(@key_path)
      end

      test "uses same key for all servers in single generation" do
        manager1 = MCP::Rails::BypassKeyManager
        key1 = manager1.key

        manager2 = MCP::Rails::BypassKeyManager
        key2 = manager2.key

        assert_equal key1, key2
      end

      test "generates new key on each server generation" do
        manager1 = MCP::Rails::BypassKeyManager
        key1 = manager1.generate_key
        manager1.save_key

        # Simulate new server generation
        manager2 = MCP::Rails::BypassKeyManager
        key2 = manager2.generate_key
        manager2.save_key

        assert_not_equal key1, key2
      end
    end
  end
end
