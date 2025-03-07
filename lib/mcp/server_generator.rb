module Mcp
  class ServerGenerator
    class << self
      def generate_file(base_url, bypass_csrf_key)
        routes_data = generate_mcp_routes
        file_path = ::Rails.root.join("tmp", "mcp", "server.rb")
        FileUtils.mkdir_p(File.dirname(file_path))
        File.open(file_path, "w") do |file|
          file.puts ruby_invocation
          file.puts
          file.puts %(require "mcp")
          file.puts %(require "httparty")
          file.puts
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

        current_mode = File.stat(file_path).mode
        new_mode = current_mode | 0111  # Add execute (u+x, g+x, o+x)
        File.chmod(new_mode, file_path)
      end

      # Recursively generates parameter definitions for the mcp-rb DSL
      def generate_parameter(param, indent_level = 1)
        indent = "  " * indent_level
        name = param[:name].to_sym
        type = (param[:type] || "string").capitalize
        required = param[:required] ? ", required: true" : ""

        if param[:nested]
          nested_params = param[:nested].map { |np| generate_parameter(np, indent_level + 1) }.join("\n")
          "#{indent}argument :#{name} #{required} do\n#{nested_params}\n#{indent}end"
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

      def ruby_invocation
        <<~RUBY
          #!/usr/bin/env ruby

          # Find the nearest Gemfile by walking up the directory tree
          def find_nearest_gemfile(start_dir)
            current_dir = File.expand_path(start_dir)
            loop do
              gemfile = File.join(current_dir, "Gemfile")
              return gemfile if File.exist?(gemfile)
              parent_dir = File.dirname(current_dir)
              break if parent_dir == current_dir # Reached root (e.g., "/")
              current_dir = parent_dir
            end
            nil # No Gemfile found
          end

          # If not already running under bundle exec, re-execute with the nearest Gemfile
          unless ENV["BUNDLE_GEMFILE"] # Check if already running under Bundler
            gemfile = find_nearest_gemfile(__dir__) # __dir__ is the script's directory
            if gemfile
              ENV["BUNDLE_GEMFILE"] = gemfile
              exec("bundle", "exec", "ruby", __FILE__, *ARGV) # Re-run with bundle exec
            else
              warn "Warning: No Gemfile found in any parent directory."
            end
          end
        RUBY
      end

      # Helper methods for HTTP requests
      def helper_methods(base_uri, bypass_csrf_key)
        <<~RUBY
          def transform_args(args)
            if args.is_a?(Hash)
              args.transform_keys { |key| key.to_s.gsub(/([a-z])([A-Z])/, '\\1_\\2').gsub(/([A-Z])([A-Z][a-z])/, '\\1_\\2').downcase }
                .transform_values { |value| transform_args(value) }
            else
              args # Return non-hash values (e.g., strings, integers) unchanged
            end
          end

          def get_resource(uri, arguments = {})
            response = HTTParty.get("#{base_uri}\#{uri}", query: transform_args(arguments), headers: { "Accept" => "application/json" })
            response.body
          end

          def post_resource(uri, payload = {})
            headers = { "Accept" => "application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            response = HTTParty.post("#{base_uri}\#{uri}", body: transform_args(payload), headers: headers)
            response.body
          end

          def patch_resource(uri, payload = {})
            headers = { "Accept" => "application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            response = HTTParty.patch("#{base_uri}\#{uri}", body: transform_args(payload), headers: headers)
            response.body
          end

          def delete_resource(uri, payload = {})
            headers = { "Accept" => "application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            response = HTTParty.delete("#{base_uri}\#{uri}", body: transform_args(payload), headers: headers)
            response.body
          end
        RUBY
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
