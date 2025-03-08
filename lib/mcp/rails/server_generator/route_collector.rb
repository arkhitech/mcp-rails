module MCP
  module Rails
    class ServerGenerator::RouteCollector
      def self.collect_routes(routes, prefix = "", engine = nil)
        routes.map do |route|
          app = route.app.app

          if app.respond_to?(:routes) && app < ::Rails::Engine
            new_prefix = [ prefix, route.path.spec.to_s ].join
            collect_routes(app.app.routes.routes, new_prefix, app)
          else
            path = [ prefix, route.path.spec.to_s ].join
            {
              route: route,
              path: path.present? ? path : route.path.spec.to_s,
              engine: engine
            }
          end
        end
      end

      def self.process_routes(routes)
        candidate_routes = routes.select do |wrapped_route|
          route = wrapped_route[:route]
          action = route.defaults[:action]&.to_s
          mcp = route.defaults[:mcp]
          mcp == true || (mcp.is_a?(Array) && action&.in?(mcp.map(&:to_s)))
        end

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
            engine: wrapped_route[:engine],
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

      def self.extract_url_params(path)
        path.scan(/:([a-zA-Z0-9_]+)/).flatten.map { |name| { name: name, type: "string", required: true } }
      end
    end
  end
end
