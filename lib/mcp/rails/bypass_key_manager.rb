require "securerandom"

module MCP
  module Rails
    class BypassKeyManager
      class << self
        def generate_key
          SecureRandom.hex(32)
        end

        def save_key(key = nil)
          key ||= generate_key
          config = MCP::Rails.configuration
          FileUtils.mkdir_p(File.dirname(config.bypass_key_path))
          File.write(config.bypass_key_path, key)
          key
        end

        def load_key
          return nil unless File.exist?(MCP::Rails.configuration.bypass_key_path)
          File.read(MCP::Rails.configuration.bypass_key_path).strip
        end

        def key
          load_key || save_key
        end

        def create_new_key
          save_key(generate_key)
        end
      end
    end
  end
end
