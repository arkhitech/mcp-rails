require "test_helper"

module MCP
  module Rails
    class ServerTest < ActionDispatch::IntegrationTest
      include MCP::Rails::TestHelper

      test "mcp_server returns the correct server" do
        mcp_tool_call(mcp_server, "index_channels")
        assert_response :success
      end

      test "mcp_servers skip verify_authenticity_token" do
        mcp_tool_call(mcp_server, "create_channels_messages", { channel_id: "1", message: { content: "test" } })
        assert_response :success
        assert_equal JSON.parse(response.body)["mcp_invocation"], true
      end
    end
  end
end
