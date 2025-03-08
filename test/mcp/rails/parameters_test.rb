require "test_helper"

module MCP
  module Rails
    class ParametersTest < ActiveSupport::TestCase
      def setup
        @temp_dir = Dir.mktmpdir
        @key_path = File.join(@temp_dir, "bypass_key.txt")
        MCP::Rails.configure do |config|
          config.bypass_key_path = @key_path
          config.base_url = "http://example.com:3000"
        end
      end

      def teardown
        FileUtils.remove_entry @temp_dir
        MCP::Rails.reset_configuration!
      end
    end
  end
end
