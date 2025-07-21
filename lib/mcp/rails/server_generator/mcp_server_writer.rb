module MCP
  module Rails
    class ServerGenerator::McpServerWriter
      def self.write_server(routes_data, config, base_url, bypass_csrf_key, engine = nil)
        # Get engine-specific configuration if available
        config = config.for_engine(engine)

        file_name = engine ? "#{config.server_name}_server.rb" : "server.rb"
        file_path = File.join(config.output_directory.to_s, file_name)
        FileUtils.mkdir_p(File.dirname(file_path))

        File.open(file_path, "w") do |file|
          file.puts "#!/usr/bin/env ruby"
          file.puts
          file.puts %(require "mcp")
          file.puts %(require "mcp/tool")
          file.puts %(require "mcp/tool/input_schema")
          file.puts %(require "mcp/tool/response")
          file.puts %(require "mcp/server/transports/stdio_transport")
          file.puts %(require "httparty")
          file.puts
          file.puts helper_methods(base_url, bypass_csrf_key, bearer_token)
          file.puts
          file.puts %(tools = [])
          routes_data.each do |route|
            file.puts %(tool = MCP::Tool.define\()
              file.puts %(  name: \"#{route[:tool_name]}\",)
              file.puts %(  description: \"#{route[:description].sub(/\//, ' ')}\",) 

              file.puts %(  input_schema: \{)
                file.puts generate_unique_parameters(route[:accepted_parameters], 2)
              file.puts %(  \})

            file.puts route_block(route, config).lines.map { |line| "  #{line}" }.join
            file.puts %(tools << tool)
            file.puts
          end
          file.puts %(server_context = {})
          env_vars = config.env_vars.map do |var|
            "server_context[:#{var.downcase}] = ENV['#{var}'] if ENV['#{var}'] && ENV['#{var}'] != ''"
          end.join("\n")
          file.puts env_vars
          file.puts %(# Create an MCP server)
          file.puts %(server = MCP::Server.new\()
          file.puts "  name: \"#{config.server_name}\"," 
          file.puts "  version: \"#{config.server_version}\"," 
          file.puts %(  server_context:,)
          file.puts %(  tools:)
          file.puts %(\)) 
          file.puts %(# Create and start the transport)
          file.puts %(transport = MCP::Server::Transports::StdioTransport.new(server))
          file.puts %(transport.open)
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
        when :array then "array"
        when :boolean then "boolean"
        when :integer then "integer"
        when :null then "null"
        when :number then "number"
        when :object then "object"
        when :string then "string"
        else "string"  # Default to String
        end
      end

      def self.bearer_token
        "Bearer #{ENV["MCP_API_KEY"]}" if ENV["MCP_API_KEY"]
      end

      def self.generate_unique_parameters(params, indent_level = 1)
        unique_params = params.uniq { |p| p[:name].to_s }
        indent = "  " * indent_level
        properties = []
        required_fields = []
        unique_params.each do |unique_param| 
          property, required = generate_parameter(unique_param, indent_level + 1)
          properties << property
          required_fields << "\"#{unique_param[:name]}\"" if required
        end
        generated_unique_parameters = ["#{indent}properties: {\n#{properties.join(",\n")}\n#{indent}}"]
        generated_unique_parameters << ",\n#{indent}required: [#{required_fields.join(', ')}]" if required_fields.any?
        generated_unique_parameters.join("")
      end
      # required(:text).filled(:string).description("Text to summarize")
      # optional(:max_length).filled(:integer).description("Maximum length of summary")
      def self.generate_parameter(param, indent_level = 1)
        indent = "  " * indent_level
        indent2 = "  " * (indent_level + 1)
        name = param[:name].to_sym
        required = param[:required]
        description = param[:description]&.gsub("\"", "\\\"")
        generated_parameter = ["#{indent}#{name}: { type: \"#{type_to_class(param[:type])}\""]
        generated_parameter << ", description: \"#{description}\"" if description
        if param[:type] == :array
          if param[:item_type]
            # Scalar array: argument :name, Array, items: Type
            generated_parameter << ", items: {\n#{indent2}type: \"#{type_to_class(param[:item_type])}\"\n#{indent}}" 
          elsif param[:nested]
            nested_params = generate_unique_parameters(param[:nested], indent_level + 1)
            generated_parameter << ", items: {\n#{indent2}type: \"object\",\n#{nested_params}\n#{indent}}"  
          else
            raise "Array parameter must have either item_type or nested parameters"
          end
        elsif param[:type] == :object && param[:nested]
          # Object: argument :name do ... end
          nested_params = generate_unique_parameters(param[:nested], indent_level + 1)
          generated_parameter << ",\n#{nested_params}"
        else
          # Scalar type: argument :name, Type
        end
        generated_parameter << "}"
        [generated_parameter.join(""), required]
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
              MCP::Tool::Response.new([{type: 'text', text: response.body}])
            else
              response_body = JSON.parse(response.body) rescue response.body
              case response_body
              when Hash                
                if response_body["errors"]
                  MCP::Tool::Response.new([{type: 'text', text: response_body.merge({error_code: response.response.code}).to_json}], true)
                else
                  MCP::Tool::Response.new([{type: 'text', text: {error_code: response.response.code, error_messages: response_body}.to_json}], true)
                end
              when String
                MCP::Tool::Response.new([{type: 'text', text: {error_code: response.response.code, error_message: response_body}.to_json}], true)
              else
                raise "Non MCP response from Rails Server"
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

        env_vars = config.env_vars.map do |var|
          "args[:#{var.downcase}] = server_context[:#{var.downcase}] if server_context[:#{var.downcase}] && server_context[:#{var.downcase}] != ''"
        end.join("\n  ")

        method = route[:method].to_s.downcase
        helper_method = "#{method}_resource"

        unique_params = route[:accepted_parameters].uniq { |p| p[:name].to_s }
        function_params = unique_params.map do |param|
          required = param[:required]
          "#{param[:name]}: #{required ? "" : "nil"}"
        end        
        function_params << "server_context:"
        arg_params = unique_params.map do |param|
          required = param[:required]
          "#{param[:name]}:"
        end.join(", ")

        <<~RUBY
        ) do |#{function_params.join(", ")}|
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
              MCP::Tool::Response.new([{type: 'text', text: response.body}])
            else
              response_body = JSON.parse(response.body) rescue response.body
              case response_body
              when Hash                
                if response_body["errors"]
                  MCP::Tool::Response.new([{type: 'text', text: response_body.merge({error_code: response.response.code}).to_json}], true)
                else
                  MCP::Tool::Response.new([{type: 'text', text: {error_code: response.response.code, error_messages: response_body}.to_json}], true)
                end
              when String
                MCP::Tool::Response.new([{type: 'text', text: {error_code: response.response.code, error_message: response_body}.to_json}], true)
              else
                raise "Non MCP response from Rails Server"
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
