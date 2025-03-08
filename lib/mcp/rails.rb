require "mcp/rails/version"
require "mcp/rails/railtie"
require "mcp/rails/configuration"
require "mcp/rails/server_generator"
require "mcp/rails/bypass_key_manager"
require "mcp/rails/server_generator/server_writer"
require "mcp/rails/server_generator/route_collector"

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
    end
  end
end
