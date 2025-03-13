#!/bin/bash

{
# Initialize request
echo '{"jsonrpc": "2.0", "method": "initialize", "params": {"protocolVersion": "2024-11-05"}, "id": 1}'

# Initialized notification
echo '{"jsonrpc": "2.0", "method": "notifications/initialized"}'

# List tools request
echo '{"jsonrpc": "2.0", "method": "tools/list", "id": 2}'

# Call greet tool request
echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "index_channels", "arguments": {}}, "id": 3}'

# Call implicit render
echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "show_channels_messages", "arguments": {"id": "1"}}, "id": 3}'

# Call fallback implicit render
echo '{"jsonrpc": "2.0", "method": "tools/call", "params": {"name": "update_channels", "arguments": {"id": "1"}}, "id": 3}'
} | ./test/dummy/tmp/mcp/server.rb