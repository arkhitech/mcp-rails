module MCP
  module Rails
    module TestHelper
      def self.included(base)
        base.setup do
          @temp_dir = Dir.mktmpdir nil, ::Rails.root.join("tmp")
          @key_path = File.join(@temp_dir, "bypass_key.txt")
          @output_dir = @temp_dir

          @old_mcp_configuration = MCP::Rails.configuration

          MCP::Rails.configure do |config|
            config.bypass_key_path = @key_path
            config.output_directory = @output_dir
          end

          @generator = MCP::Rails::ServerGenerator
          @server_files = @generator.generate_files
        end

        base.teardown do
          FileUtils.remove_entry @temp_dir
          MCP::Rails.configuration = @old_mcp_configuration
        end
      end

      def mcp_servers
        @mcp_servers = @server_files.map do |file|
          require file
          at_exit { MCP.instance_variable_set(:@server, nil) }
          initialize_server(MCP.server)
          MCP.server
        end
      end

      def mcp_server(name: "mcp-server")
        mcp_servers.find { |server| server.name == name }
      end

      def mcp_tool_list(server)
        request = {
          jsonrpc: MCP::Constants::JSON_RPC_VERSION,
          method: MCP::Constants::RequestMethods::TOOLS_LIST,
          id: 1
        }

        send_request(server, request)
      end

      def mcp_tool_call(server, name, arguments = {})
        request = {
          jsonrpc: MCP::Constants::JSON_RPC_VERSION,
          id: 1,
          method: MCP::Constants::RequestMethods::TOOLS_CALL,
          params: {
            name: name,
            arguments: arguments.merge({ test_context: self })
          }
        }
        send_request(server, request)
      end

      private

      def send_request(server, request)
        response = server.send(:handle_request, request)
        raise "Request failed: #{response}" unless response.dig(:result, :isError) == false
        response
      end

      def initialize_server(server)
        init_request = {
          jsonrpc: MCP::Constants::JSON_RPC_VERSION,
          method: "initialize",
          params: {
            protocolVersion: MCP::Constants::PROTOCOL_VERSION,
            capabilities: {}
          },
          id: 1
        }
        initialize_response = server.send(:handle_request, init_request)

        init_notification = {
          jsonrpc: MCP::Constants::JSON_RPC_VERSION,
          method: "notifications/initialized",
          id: 2
        }
        server.send(:handle_request, init_notification)

        initialize_response
      end
    end
  end
end
