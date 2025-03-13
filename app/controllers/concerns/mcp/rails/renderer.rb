# lib/mcp/rails/renderer.rb
module MCP
  module Rails
    module Renderer
      extend ActiveSupport::Concern

      included do
        alias_method :original_render, :render
        alias_method :render, :mcp_render
      end

      def mcp_render(*args)
        return original_render(*args) unless request.format.mcp?

        options = args.extract_options!
        if implicit_jbuilder_render?(options)
          process_implicit_jbuilder_render(options)
        elsif options[:json] || options[:mcp]
          process_explicit_render(options)
        end
        original_render(*args, options)
      end

      private

      def implicit_jbuilder_render?(options)
        options.empty? &&
        lookup_context.exists?(action_name, lookup_context.prefixes, false, [], formats: [ :mcp, :json ], handlers: [ :jbuilder ])
      end

      def process_implicit_jbuilder_render(options)
        template = lookup_context.find(action_name, lookup_context.prefixes, false, [], formats: [ :mcp, :json ], handlers: [ :jbuilder ])
        data = JbuilderTemplate.new(view_context, key_format: :camelize) do |json|
          json.key_format! camelize: :lower
          view_context.instance_exec(json) do |j|
            eval(template.source, binding, template.identifier)
          end
        end.attributes!
        # Wrap in status/data structure
        options[:json] = {
          status: Rack::Utils.status_code(response.status || :ok),
          data: data
        }
      end

      def process_explicit_render(options)
        status_code = Rack::Utils.status_code(options[:status] || :ok)
        data = options.delete(:mcp) || options.delete(:json)

        # Wrap in status/data structure
        options[:json] = {
          status: status_code,
          data: format_keys(data)
        }
      end

      def format_keys(data)
        case data
        when Hash
          data.deep_transform_keys { |k| k.to_s.camelize(:lower) }
        when Array
          data.map { |item| format_keys(item) }
        else
          data
        end
      end
    end
  end
end
