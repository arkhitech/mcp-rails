module Mcp
  class ServerGenerator
    class << self
      def generate_file(base_url, bypass_csrf_key)
        routes_data = generate_mcp_routes
        file_path = ::Rails.root.join("tmp", "mcp", "server.rb")
        FileUtils.mkdir_p(File.dirname(file_path))
        File.open(file_path, "w") do |file|
          file.puts %(require "mcp")
          file.puts %(require "httparty")
          file.puts %(require "nokogiri")
          file.puts helper_methods(base_url, bypass_csrf_key)
          file.puts
          file.puts %(name "test-server")
          file.puts %(version "1.0.0")
          routes_data.each do |route|
            file.puts %(tool "#{route[:tool_name]}" do)
            file.puts "  description \"#{route[:description]}\""
            route[:accepted_parameters].each do |param|
              file.puts generate_parameter(param)
            end
            file.puts route_block(route).lines.map { |line| "  #{line}" }.join
            file.puts "end"
            file.puts
          end
        end
      end

      # Recursively generates parameter definitions for the mcp-rb DSL
      def generate_parameter(param, indent_level = 1)
        indent = "  " * indent_level
        name = param[:name].to_sym
        type = (param[:type] || "string").capitalize
        required = param[:required] ? ", required: true" : ""

        if param[:nested]
          nested_params = param[:nested].map { |np| generate_parameter(np, indent_level + 1) }.join("\n")
          "#{indent}argument :#{name}, Object#{required} do\n#{nested_params}\n#{indent}end"
        else
          "#{indent}argument :#{name}, #{type}#{required}"
        end
      end

      def collect_routes(routes, prefix = "")
        routes.map do |route|
          app = route.app.app

          if app.respond_to?(:routes) && app < ::Rails::Engine
            new_prefix = [ prefix, route.path.spec.to_s ].join
            collect_routes(app.app.routes.routes, new_prefix)
          else
            path = [ prefix, route.path.spec.to_s ].join
            { route: route, path: path.present? ? path : route.path.spec.to_s }
          end
        end
      end

      def generate_mcp_routes
        routes = collect_routes(::Rails.application.routes.routes, routes).flatten

        candidate_routes = routes.select do |wrapped_route|
          route = wrapped_route[:route]
          mcp = route.defaults[:mcp]
          mcp == true || (mcp.is_a?(Array) && route.defaults[:action]&.to_s&.in?(mcp.map(&:to_s)))
        end

        # Step 3: Process routes into tool definitions
        candidate_routes.map do |wrapped_route|
          route = wrapped_route[:route]
          next unless route.defaults[:controller] && route.defaults[:action]
          next unless route.defaults[:action].to_s.in?(%w[create index show update destroy])
          next if route.verb.downcase == "put"

          begin
            controller_class = "#{route.defaults[:controller].camelize}Controller".constantize
            action = route.defaults[:action].to_sym
            params_def = controller_class.permitted_params(action)
          rescue NameError
            raise
            next
          end

          full_path = (wrapped_route[:path] || route.path.spec.to_s).sub(/\(\.:format\)$/, "") || ""
          url_params = extract_url_params(full_path)
          params_def += url_params unless params_def.any? { |p| url_params.map { |up| up[:name] }.include?(p[:name]) }

          {
            tool_name: "#{action}_#{route.defaults[:controller].parameterize}",
            description: "Handles #{action} for #{route.defaults[:controller]}",
            method: route.verb.downcase.to_sym,
            path: full_path,
            url_parameters: url_params,
            accepted_parameters: params_def.map do |param|
              {
                name: param[:name],
                type: param[:type] || String,
                required: param[:required],
                nested: param[:nested]&.map { |n| { name: n[:name], type: n[:type], required: n[:required] } }
              }.compact
            end
          }
        end.compact
      end

      # Extracts URL parameters from a path string
      def extract_url_params(path)
        path.scan(/:([a-zA-Z0-9_]+)/).flatten.map { |name| { name: name, type: "string", required: true } }
      end

      # Helper methods for HTTP requests
      def helper_methods(base_uri, bypass_csrf_key)
        <<~METHODS
          def get_resource(uri, arguments = {})
            response = HTTParty.get("#{base_uri}\#{uri}", query: arguments, headers: { "Accept" => "application/json" })
            response.body
          end

          def post_resource(uri, payload = {})
            headers = { "Accept" => "application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            response = HTTParty.post("#{base_uri}\#{uri}", body: payload, headers: headers)
            response.body
          end

          def patch_resource(uri, payload = {})
            headers = { "Accept" => "application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            response = HTTParty.patch("#{base_uri}\#{uri}", body: payload, headers: headers)
            response.body
          end

          def delete_resource(uri, payload = {})
            headers = { "Accept" => "application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            response = HTTParty.delete("#{base_uri}\#{uri}", body: payload, headers: headers)
            response.body
          end
        METHODS
      end

      def route_block(route)
        uri = route[:path]
        route[:url_parameters].each do |url_parameter|
          uri = uri.gsub(":#{url_parameter[:name]}", "\#{args[:#{url_parameter[:name]}]}")
        end
        <<~ROUTE
          call do |args|
            #{route[:method]}_resource "#{uri}", args.except(*#{route[:url_parameters].map { |p| p[:name] }})
          end
        ROUTE
      end
    end
  end
end