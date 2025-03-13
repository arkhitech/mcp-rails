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
        assert_equal mcp_response_body["mcpInvocation"], true
      end

      test "implicit mcp views are prioritized over json" do
        mcp_tool_call(mcp_server, "show_channels_messages", { id: "1" })
        assert_response :success
        assert_equal mcp_response_body["content"], "mcp test"
        assert mcp_response_body.has_key?("mcpInvocation")
      end

      test "fall back to implicit json" do
        mcp_tool_call(mcp_server, "update_channels", { id: "1" })
        assert_response :success
        assert_equal mcp_response_body["content"], "json test"
        assert mcp_response_body.has_key?("mcpInvocation")
      end

      test "explicit mcp views are prioritized over json" do
        mcp_tool_call(mcp_server, "show_channels", { id: "1" })
        assert_response :success
        assert_equal mcp_response_body["name"], "mcp_test"
      end

      test "mcp views fallback to explicit json views" do
        mcp_tool_call(mcp_server, "destroy_channels", { id: "1" })
        assert_response :success
        assert_equal mcp_response_body["name"], "json fallback test"
      end

      test "mcp renderer does not affect rendering of json" do
        get channels_path(1), as: :json
        assert_response :success
        assert_equal "[{\"name\":\"test\",\"user_ids\":[\"1\",\"2\"]}]", response.body

        get message_path(1), as: :json
        assert_equal "{\"content\":\"json test\"}", response.body
      end
    end
  end
end
