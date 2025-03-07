module MCP
  module Rails
    module ServerGenerator
      class BypassKeyManager
        def self.generate_key
          SecureRandom.hex(32)
        end

        def self.save_key(key)
          config = MCP::Rails.configuration
          FileUtils.mkdir_p(File.dirname(config.bypass_key_path))
          File.write(config.bypass_key_path, key)
          key
        end

        def self.create_new_key
          save_key(generate_key)
        end
      end
    end
  end
end
