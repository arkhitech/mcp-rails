module MCP
  module Rails
    class ServerGenerator
      class << self
        def generate_file
          config = MCP::Rails.configuration
          base_url = config.base_url
          bypass_csrf_key = BypassKeyManager.create_new_key

          # Collect all routes including engine routes
          all_routes = RouteCollector.collect_routes(::Rails.application.routes.routes).flatten

          # Group routes by engine
          grouped_routes = all_routes.group_by { |r| r[:engine] }

          # Generate server files for each group
          generated_files = []

          # Process main app routes
          main_app_routes = RouteCollector.process_routes(grouped_routes[nil] || [])
          if main_app_routes.any?
            file_path = ServerWriter.write_server(
              main_app_routes,
              config,
              base_url,
              bypass_csrf_key
            )
            generated_files << file_path
          end

          # Process each engine's routes
          grouped_routes.each do |engine, routes|
            next unless engine # Skip main app routes which we processed above

            engine_routes = RouteCollector.process_routes(routes)
            next unless engine_routes.any?

            file_path = ServerWriter.write_server(
              engine_routes,
              config,
              base_url,
              bypass_csrf_key,
              engine
            )
            generated_files << file_path
          end

          generated_files
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
          config = MCP::Rails.configuration
          uri = route[:path]
          route[:url_parameters].each do |url_parameter|
            uri = uri.gsub(":#{url_parameter[:name]}", "\#{args[:#{url_parameter[:name]}]}")
          end

          env_vars = config.env_vars.map do |var|
            "      args[:#{var.downcase}] = ENV['#{var}']"
          end.join("\n")

          <<~ROUTE
            call do |args|
              # Add configured environment variables
#{env_vars}
              #{route[:method]}_resource "#{uri}", args.except(*#{route[:url_parameters].map { |p| p[:name] }})
            end
          ROUTE
        end
      end
    end
  end
end
