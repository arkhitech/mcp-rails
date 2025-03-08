require "test_helper"

module MCP
  module Rails
    class ConfigurationTest < ActiveSupport::TestCase
      def setup
        @temp_dir = Dir.mktmpdir
        @key_path = File.join(@temp_dir, "bypass_key.txt")
        @output_dir = File.join(@temp_dir, "server.rb")
      end

      def teardown
        FileUtils.remove_entry @temp_dir
        MCP::Rails.reset_configuration!
      end

      test "provides default configuration values" do
        config = MCP::Rails.configuration
        config.env_vars = [ "API_KEY", "ORGANIZATION_ID" ]

        assert_equal ::Rails.root.join("tmp", "mcp", "bypass_key.txt").to_s, config.bypass_key_path.to_s
        assert_equal ::Rails.root.join("tmp", "mcp").to_s, config.output_directory.to_s
        assert_equal "mcp-server", config.server_name
        assert_equal "1.0.0", config.server_version
        assert_includes config.env_vars, "API_KEY"
        assert_includes config.env_vars, "ORGANIZATION_ID"
      end

      test "allows configuration modification" do
        MCP::Rails.configure do |config|
          config.bypass_key_path = @key_path
          config.output_directory = @temp_dir
          config.server_name = "test-server"
          config.server_version = "2.0.0"
          config.env_vars = [ "TEST_API_KEY" ]
        end

        config = MCP::Rails.configuration
        assert_equal @key_path, config.bypass_key_path.to_s
        assert_equal @temp_dir, config.output_directory.to_s
        assert_equal "test-server", config.server_name
        assert_equal "2.0.0", config.server_version
        assert_equal [ "TEST_API_KEY" ], config.env_vars
      end

      test "base_url fallback behavior" do
        # Store and reset action_mailer settings
        old_default_url_options = ::Rails.application.config.action_mailer.default_url_options
        ::Rails.application.config.action_mailer.default_url_options = nil

        # Test default fallback to localhost:3000
        config = MCP::Rails.configuration
        assert_equal "http://localhost:3000", config.base_url

        # Test action_mailer fallback
        ::Rails.application.config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
        MCP::Rails.reset_configuration!
        assert_equal "http://localhost:3000", MCP::Rails.configuration.base_url

        # Test explicit configuration
        MCP::Rails.configure do |config|
          config.base_url = "https://test.example.com"
        end
        assert_equal "https://test.example.com", MCP::Rails.configuration.base_url

        # Restore action_mailer settings
        ::Rails.application.config.action_mailer.default_url_options = old_default_url_options
      end
    end
  end
end
