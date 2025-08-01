module MCP
  module Rails
    class ServerGenerator::McpRbServerWriter < ServerGenerator::ServerWriter
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
          file.puts %(require "httparty")
          file.puts
          file.puts helper_methods(base_url, bypass_csrf_key, bearer_token)
          file.puts

          file.puts %(name "#{config.server_name}")
          file.puts %(version "#{config.server_version}")

          routes_data.each do |route|
            file.puts %(tool "#{route[:tool_name].underscore}" do)
            file.puts "  description \"#{route[:description].sub(/\//, ' ')}\""
            generate_unique_parameters(route[:accepted_parameters]).each do |param|
              file.puts param
            end
            file.puts route_block(route, config).lines.map { |line| "  #{line}" }.join
            file.puts "end"
            file.puts
          end
        end

        current_mode = File.stat(file_path).mode
        new_mode = current_mode | 0111  # Add execute (u+x, g+x, o+x)
        File.chmod(new_mode, file_path)

        file_path
      end

      def self.type_to_class(type)
        case type
        when :string then "String"
        when :integer then "Integer"
        when :number then "Float"
        when :boolean then "TrueClass"
        when :array then "Array"
        else "String"  # Default to String
        end
      end

      def self.generate_unique_parameters(params, indent_level = 1)
        unique_params = params.uniq { |p| p[:name].to_s }
        unique_params.map { |np| generate_parameter(np, indent_level + 1) }
      end

      def self.generate_parameter(param, indent_level = 1)
        indent = "  " * indent_level
        name = param[:name].to_sym
        required = param[:required] ? ", required: true" : ""
        description = param[:description] ? ", description: \"#{param[:description]}\"" : ""

        if param[:type] == :array
          if param[:item_type]
            # Scalar array: argument :name, Array, items: Type
            type_str = "Array, items: #{type_to_class(param[:item_type])}"
            "#{indent}argument :#{name}, #{type_str}#{required}#{description}"
          elsif param[:nested]
            # Array of objects: argument :name, Array do ... end
            nested_params = generate_unique_parameters(param[:nested], indent_level + 1).join("\n")
            "#{indent}argument :#{name}, Array#{required}#{description} do\n#{nested_params}\n#{indent}end"
          else
            raise "Array parameter must have either item_type or nested parameters"
          end
        elsif param[:type] == :object && param[:nested]
          # Object: argument :name do ... end
          nested_params = generate_unique_parameters(param[:nested], indent_level + 1).join("\n")
          "#{indent}argument :#{name}#{required}#{description} do\n#{nested_params}\n#{indent}end"
        else
          # Scalar type: argument :name, Type
          type_str = type_to_class(param[:type])
          "#{indent}argument :#{name}, #{type_str}#{required}#{description}"
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
                  {error_code: response.response.code, error_messages: response_body}.to_json
                end
              when String
                {error_code: response.response.code, error_message: response_body}.to_json
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
            headers["Authorization"] = #{bearer_token.present? ? "#{bearer_token}" : 'ENV["AUTHORIZATION"]'}
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
          "args[:#{var.downcase}] = ENV['#{var}'] if ENV['#{var}']"
        end.join("\n")

        method = route[:method].to_s.downcase
        helper_method = "#{method}_resource"

        <<~RUBY
          call do |args|
            #{env_vars}
            #{helper_method}("#{uri}", args)
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
