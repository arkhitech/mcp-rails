namespace :mcp do
  namespace :rails do
    desc "Generate MCP server file"
    task generate_server: :environment do
      # Generate server files
      MCP::Rails::ServerGenerator.generate_files
    end
  end
end
