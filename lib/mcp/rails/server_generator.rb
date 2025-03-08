module MCP
  module Rails
    class ServerGenerator
      class << self
        def generate_files
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
      end
    end
  end
end
