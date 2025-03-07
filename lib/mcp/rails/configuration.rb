module MCP
  module Rails
    class Configuration
      # Server configuration
      attr_accessor :server_name, :server_version
      
      # Output configuration
      attr_accessor :output_directory, :bypass_key_path
      
      # Environment variables to include in tool calls
      attr_accessor :env_vars

      # Engine configurations
      attr_reader :engine_configurations
      
      def initialize
        # Server defaults
        @server_name = 'mcp-server'
        @server_version = '1.0.0'
        
        # Output defaults
        @output_directory = ::Rails.root.join('tmp', 'mcp') if defined?(::Rails)
        @bypass_key_path = ::Rails.root.join('tmp', 'mcp', 'bypass_key.txt') if defined?(::Rails)
        
        # Environment variables to include in tool calls
        @env_vars = ['API_KEY', 'ORGANIZATION_ID']

        # Initialize engine configurations hash
        @engine_configurations = {}
      end

      def base_url
        return @base_url if defined?(@base_url)
        
        if defined?(::Rails)
          mailer_options = ::Rails.application.config.action_mailer.default_url_options || {}
          host = mailer_options[:host] || "localhost"
          port = mailer_options[:port] || "3000"
          protocol = mailer_options[:protocol] || "http"
          "#{protocol}://#{host}:#{port}"
        else
          'http://localhost:3000'
        end
      end

      def base_url=(url)
        @base_url = url
      end

      # Register an engine's configuration
      def register_engine(engine_name, settings = {})
        @engine_configurations[engine_name.to_s] = EngineConfiguration.new(settings)
      end

      # Get configuration for a specific engine
      def for_engine(engine)
        return self unless engine
        engine_name = engine.engine_name.to_s
        engine_config = @engine_configurations[engine_name]
        return self unless engine_config

        # Create a merged configuration
        merged_config = self.dup
        merged_config.instance_variable_set(:@env_vars, (self.env_vars + engine_config.env_vars).uniq)
        merged_config
      end
    end

    class EngineConfiguration
      attr_reader :env_vars

      def initialize(settings = {})
        @env_vars = Array(settings[:env_vars] || [])
      end
    end
  end
end
