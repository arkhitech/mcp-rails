require "mcp/rails/version"
require "mcp/rails/railtie"
require "mcp/rails/configuration"
require "mcp/rails/server_generator"
require "mcp/rails/bypass_key_manager"
require "mcp/rails/server_generator/server_writer"
require "mcp/rails/server_generator/fast_server_writer"
require "mcp/rails/server_generator/route_collector"
require_relative "../../test/support/mcp/rails/test_helper"

module MCP
  module Rails
    class << self
      def configuration
        @configuration ||= Configuration.new
      end

      def configure
        yield(configuration)
      end

      def reset_configuration!
        @configuration = Configuration.new
      end

      def configuration=(configuration)
        raise ArgumentError, "configuration must be an instance of MCP::Rails::Configuration" unless configuration.is_a?(Configuration)
        @configuration = configuration
      end
    end
  end
end
