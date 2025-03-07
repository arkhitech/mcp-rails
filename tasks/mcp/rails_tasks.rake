namespace :mcp do
  desc "Generate MCP Server"
  task generate_server: :environment do
    gem_root = Gem::Specification.find_by_name("mcp-rails").gem_dir
    require File.join(gem_root, "lib/mcp/server_generator.rb")
    mailer_options = ::Rails.application.config.action_mailer.default_url_options || {}
    host = mailer_options[:host] || "localhost"
    port = mailer_options[:port] || "3000"
    protocol = mailer_options[:protocol] || "http"
    base_url = "#{protocol}://#{host}:#{port}"
    bypass_csrf_key = SecureRandom.hex(32)
    file_path = ::Rails.root.join("tmp", "mcp", "bypass_key.txt")
    FileUtils.mkdir_p(File.dirname(file_path))
    File.write(file_path, bypass_csrf_key)
    Mcp::ServerGenerator.generate_file(base_url, bypass_csrf_key)
  end
end
