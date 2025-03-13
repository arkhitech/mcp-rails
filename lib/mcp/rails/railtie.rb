module Mcp
  module Rails
    class Railtie < ::Rails::Railtie
      railtie_name "mcp-rails"
      gem_root = Gem::Specification.find_by_name("mcp-rails").gem_dir

      config.to_prepare do
        require File.join(gem_root, "app/controllers/concerns/mcp/rails/parameters")
        require File.join(gem_root, "app/controllers/concerns/mcp/rails/tool_descriptions")
        require File.join(gem_root, "app/controllers/concerns/mcp/rails/error_handling")
        require File.join(gem_root, "app/controllers/concerns/mcp/rails/renderer")
        ActionController::Base.include(MCP::Rails::Parameters)
        ActionController::Base.include(MCP::Rails::ToolDescriptions)
        ActionController::Base.include(MCP::Rails::ErrorHandling)
        ActionController::Base.include(MCP::Rails::Renderer)
      end

      initializer "mcp-rails.mime_type" do
        Mime::Type.register "application/vnd.mcp+json", :mcp# , [ "application/json" ]
      end

      initializer "mcp-rails.renderer" do
        ActionController::Renderers.add :mcp do |mcp_json, options|
          self.content_type = Mime[:mcp] if media_type.nil?
          mcp_json
        end
      end

      initializer "mcp-rails.integration_test_request_encoding" do
        ActiveSupport.on_load(:action_dispatch_integration_test) do
          # Support `as: :mcp`. Public `register_encoder` API is a little too strict.
          class ActionDispatch::RequestEncoder
            class McpEncoder < IdentityEncoder
              header = [ Mime[:mcp], Mime[:json] ].join(",")
              define_method(:accept_header) { header }
            end

            @encoders[:mcp] = McpEncoder.new
          end
        end
      end

      rake_tasks do
        path = File.expand_path("#{gem_root}/tasks/mcp", __dir__)
        Dir.glob("#{path}/*.rake").each { |f| load f }
      end
    end
  end
end
