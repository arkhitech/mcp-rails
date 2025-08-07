module MCP
  module Rails
    class ServerGenerator
      class << self
        def generate_files(config = MCP::Rails.configuration)
          base_url = config.base_url
          bypass_csrf_key = BypassKeyManager.create_new_key

          all_routes = RouteCollector.collect_routes(::Rails.application.routes.routes).flatten
          grouped_routes = all_routes.group_by { |r| r[:engine] }

          generated_files = []

          # Process main app routes
          main_app_routes = grouped_routes[nil].select { |r| r[:route].defaults[:mcp_servers].nil? }
          main_app_routes = RouteCollector.process_routes(grouped_routes[nil] || [])
          writer_class = (config.mcp_server_type && config.mcp_server_type != 'mcp') ? (config.mcp_server_type == 'fast' ? FastServerWriter : McpRbServerWriter) : McpServerWriter
          if main_app_routes.any?
            file_path = writer_class.write_server(
              main_app_routes,
              config.for_engine(nil),
              base_url,
              bypass_csrf_key
            )
            generated_files << file_path
            writer_class.write_wrapper_script(config, file_path)
            generated_files << file_path
          end

          # Process each engine's routes
          grouped_routes.each do |engine, routes|
            next unless engine

            engine_routes = RouteCollector.process_routes(routes)
            next unless engine_routes.any?

            engine_config = config.for_engine(engine)
            file_path = writer_class.write_server(
              engine_routes,
              engine_config,
              base_url,
              bypass_csrf_key
            )
            generated_files << file_path
            writer_class.write_wrapper_script(config, file_path)
            generated_files << file_path
          end

          grouped_by_servers = {}
          all_routes.each do |route|
            if route[:route].defaults[:mcp_servers]
              route[:route].defaults[:mcp_servers].each do |server|
                grouped_by_servers[server] ||= []
                grouped_by_servers[server] << route
              end
            end
          end
          
          # Process each engine's routes
          grouped_by_servers.each do |server_name, routes|
            server_routes = RouteCollector.process_routes(routes || [])
            
            server_config = config.for_server(server_name)
            file_path = writer_class.write_server(
              server_routes,
              server_config,
              base_url,
              bypass_csrf_key
            )
            generated_files << file_path
            writer_class.write_wrapper_script(config, file_path)
            generated_files << file_path
          end

          generated_files
        end
      end
    end
  end
end
