module MCP
  module Rails
    class ServerGenerator::FastServerWriter
      def self.write_server(routes_data, config, base_url, bypass_csrf_key, engine = nil)
        # Get engine-specific configuration if available
        config = config.for_engine(engine)

        file_name = engine ? "#{config.server_name}_server.rb" : "server.rb"
        file_path = File.join(config.output_directory.to_s, file_name)
        FileUtils.mkdir_p(File.dirname(file_path))

        File.open(file_path, "w") do |file|
          file.puts "#!/usr/bin/env ruby"
          file.puts
          file.puts %(require "fast_mcp")
          file.puts %(require "httparty")
          file.puts
          file.puts helper_methods(base_url, bypass_csrf_key, bearer_token)
          file.puts

          file.puts %(# Create an MCP server)
          file.puts %(server = FastMcp::Server.new(name: "#{config.server_name}", version: "#{config.server_version}")) 
          routes_data.each do |route|
            file.puts %(# Define a tool by inheriting from FastMcp::Tool)
            tool_class_name = "#{route[:tool_name].underscore.camelize}Tool"
            file.puts %(class #{tool_class_name} < FastMcp::Tool)
              file.puts %( description \"#{route[:description].sub(/\//, ' ')}\")

              file.puts %( arguments do)
                generate_unique_parameters(route[:accepted_parameters], 2).each do |param|
                  file.puts param
                end
              file.puts %( end)

              file.puts route_block(route, config).lines.map { |line| "  #{line}" }.join
            file.puts %(end)
            file.puts
            file.puts %(server.register_tool(#{tool_class_name}))
          end
          file.puts %(# Start the server)
          file.puts %(server.start)

        end

        current_mode = File.stat(file_path).mode
        new_mode = current_mode | 0111  # Add execute (u+x, g+x, o+x)
        File.chmod(new_mode, file_path)

        file_path
      end

      def self.write_wrapper_script(config, server_rb_path, engine = nil)
        # Get engine-specific configuration if available
        config = config.for_engine(engine)

        server_rb = engine ? "#{config.server_name}_server.rb" : "server.rb"
        wrapper_file_name = engine ? "#{config.server_name}_server.sh" : "server.sh"
        wrapper_file_path = File.join(config.output_directory.to_s, wrapper_file_name)
        FileUtils.mkdir_p(File.dirname(wrapper_file_path))

        # Determine paths and environment variables
        bundle_gemfile = ENV["BUNDLE_GEMFILE"] || self.find_nearest_gemfile(config.output_directory.to_s) || ""
        gem_home = Gem.paths.home
        gem_path = Gem.paths.path.join(":")
        bundle_path = ENV["BUNDLE_PATH"] || gem_home # Use BUNDLE_PATH if set, else default to GEM_HOME
        ruby_executable = RbConfig.ruby # Get the path to the current Ruby executable

        # Construct the wrapper script content
        script_content = <<~SHELL
          #!/bin/bash

          export BUNDLE_GEMFILE=#{bundle_gemfile.shellescape}
          export GEM_HOME=#{gem_home.shellescape}
          export GEM_PATH=#{gem_path.shellescape}
          export BUNDLE_PATH=#{bundle_path.shellescape}
          export PATH=#{File.dirname(ruby_executable).shellescape}:$PATH
          export LANG=en_US.UTF-8

          DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

          exec "#{ruby_executable.shellescape}" "${DIR}/#{server_rb}" "$@"
        SHELL

        # Write the script file
        File.open(wrapper_file_path, "w") do |file|
          file.puts script_content
        end

        # Make the script executable
        current_mode = File.stat(wrapper_file_path).mode
        new_mode = current_mode | 0111 # Add execute (u+x, g+x, o+x)
        File.chmod(new_mode, wrapper_file_path)

        wrapper_file_path
      end

      def self.find_nearest_gemfile(start_dir)
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

      def self.type_to_class(type)
        case type
        when :string then "string"
        when :integer then "integer"
        when :number then "float"
        when :boolean then "bool"
        when :array then "array"
        else "string"  # Default to String
        end
      end

      def self.bearer_token
        "Bearer #{ENV["MCP_API_KEY"]}" if ENV["MCP_API_KEY"]
      end

      def self.generate_unique_parameters(params, indent_level = 1)
        unique_params = params.uniq { |p| p[:name].to_s }
        unique_params.map { |np| generate_parameter(np, indent_level + 1) }
      end

      # required(:text).filled(:string).description("Text to summarize")
      # optional(:max_length).filled(:integer).description("Maximum length of summary")
      def self.generate_parameter(param, indent_level = 1)
        indent = "  " * indent_level
        name = param[:name].to_sym
        required = param[:required]
        param_name_wrapper = required ? "required" : "optional"
        description = param[:description]&.gsub("\"", "\\\"")

        if param[:type] == :array
          if param[:item_type]
            # Scalar array: argument :name, Array, items: Type
            type_str = type_to_class(param[:item_type])
            # "#{indent}argument :#{name}, #{type_str}#{required}#{description}"
            "#{indent}#{param_name_wrapper}(:#{name}).array(:#{type_str}).description(\"#{description}\")"
          elsif param[:nested]
            # Array of objects: argument :name, Array do ... end
            nested_params = generate_unique_parameters(param[:nested], indent_level + 1).join("\n")
            # "#{indent}argument :#{name}, Array#{required}#{description} do\n#{nested_params}\n#{indent}end"
            "#{indent}#{param_name_wrapper}(:#{name}).description(\"#{description}\").array(:hash) do\n#{nested_params}\n#{indent}end"
          else
            raise "Array parameter must have either item_type or nested parameters"
          end
        elsif param[:type] == :object && param[:nested]
          # Object: argument :name do ... end
          nested_params = generate_unique_parameters(param[:nested], indent_level + 1).join("\n")
          param_name_wrapper = required ? "required" : "optional"
          "#{indent}#{param_name_wrapper}(:#{name}).description(\"#{description}\").hash do\n#{nested_params}\n#{indent}end"
        else
          # Scalar type: argument :name, Type
          type_str = type_to_class(param[:type])
          "#{indent}#{param_name_wrapper}(:#{name}).filled(:#{type_str}).description(\"#{description}\")"
        end
      end

      def self.helper_methods(base_uri, bypass_csrf_key, bearer_token)
        return test_helper_methods(base_uri, bypass_csrf_key) if ::Rails.env.test?
        <<~RUBY
          def transform_args(args)
            if args.is_a?(Hash)
              args.transform_keys { |key| key.to_s.gsub(/([a-z])([A-Z])/, '\\1_\\2').gsub(/([A-Z])([A-Z][a-z])/, '\\1_\\2').downcase }
                .transform_values { |value| transform_args(value) }
            else
              args # Return non-hash values (e.g., strings, integers) unchanged
            end
          end

          def parse_response(response)
            if response.success?
              response.body
            else
              response_body = JSON.parse(response.body) rescue response.body
              case response_body
              when Hash                
                if response_body["errors"]
                  response_body.merge({error_code: response.response.code}).to_json  
                else
                  {error_code: response.response.code}.to_json
                end
              when String
                {error_code: response.response.code, error_message: response_body}.to_json
              else
                raise "None MCP response from Rails Server"
              end
            end
          rescue => e
            raise "Parsing JSON failed: \#{e.message}"
          end

          def http_headers
            headers = { "Accept" => "application/vnd.mcp+json, application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            headers["Authorization"] = #{bearer_token.present? ? "Bearer #{bearer_token}" : 'ENV["AUTHORIZATION"]'}
            headers
          end

          def get_resource(uri, arguments = {})
            headers = http_headers
            response = HTTParty.get("#{base_uri}\#{uri}", query: transform_args(arguments), headers:)
            parse_response(response)
          end

          def post_resource(uri, payload = {})
            headers = http_headers
            response = HTTParty.post("#{base_uri}\#{uri}", body: transform_args(payload), headers:)
            parse_response(response)
          end

          def patch_resource(uri, payload = {})
            headers = http_headers
            response = HTTParty.patch("#{base_uri}\#{uri}", body: transform_args(payload), headers:)
            parse_response(response)
          end

          def delete_resource(uri, payload = {})
            headers = http_headers
            response = HTTParty.delete("#{base_uri}\#{uri}", body: transform_args(payload), headers:)
            parse_response(response)
          end
        RUBY
      end

      def self.route_block(route, config)
        uri = route[:path]
        route[:url_parameters].each do |url_parameter|
          uri = uri.gsub(":#{url_parameter[:name]}", "\#{args[:#{url_parameter[:name]}]}")
        end

        unique_params = route[:accepted_parameters].uniq { |p| p[:name].to_s }
        function_params = unique_params.map do |param|
          required = param[:required]
          "#{param[:name]}: #{required ? "" : "nil"}"
        end.join(", ")

        arg_params = unique_params.map do |param|
          required = param[:required]
          "#{param[:name]}:"
        end.join(", ")

        env_vars = config.env_vars.map do |var|
          "args[:#{var.downcase}] = ENV['#{var}'] if ENV['#{var}']"
        end.join("\n  ")

        method = route[:method].to_s.downcase
        helper_method = "#{method}_resource"

        <<~RUBY
          def call(#{function_params})
            args = {#{arg_params}}
            #{env_vars}
            #{helper_method}("#{uri}", args.compact)
          end
        RUBY
      end

      def self.test_helper_methods(base_uri, bypass_csrf_key)
        <<~RUBY
          def parse_response(response)
            if response.success?
              response.body
            else
              response_body = JSON.parse(response.body) rescue response.body
              case response_body
              when Hash                
                if response_body["errors"]
                  response_body.merge({error_code: response.response.code}).to_json  
                else
                  {error_code: response.response.code}.to_json
                end
              when String
                {error_code: response.response.code, error_message: response_body}.to_json
              else
                raise "None MCP response from Rails Server"
              end
            end
          rescue => e
            raise "Parsing JSON failed: \#{e.message}"
          end


          def get_resource(uri, arguments = {})
            test_context = arguments.delete(:test_context)
            test_context.get uri, params: arguments, headers: { "Accept" => "application/vnd.mcp+json, application/json" }, as: :mcp
            parse_response(test_context)
          end

          def post_resource(uri, payload = {}, headers = {})
            test_context = payload.delete(:test_context)
            headers = { "Accept" => "application/vnd.mcp+json, application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            test_context.post uri, params: payload, headers: headers, as: :mcp
            parse_response(test_context)
          end

          def patch_resource(uri, payload = {})
            test_context = payload.delete(:test_context)
            headers = { "Accept" => "application/vnd.mcp+json, application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            test_context.patch uri, params: payload.merge(headers: headers), as: :mcp
            parse_response(test_context)
          end

          def delete_resource(uri, payload = {})
            test_context = payload.delete(:test_context)
            headers = { "Accept" => "application/vnd.mcp+json, application/json" }
            headers["X-Bypass-CSRF"] = "#{bypass_csrf_key}"
            test_context.delete uri, params: payload.merge(headers: headers), as: :mcp
            parse_response(test_context)
          end
        RUBY
      end
    end
  end
end
