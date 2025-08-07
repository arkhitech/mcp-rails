module MCP
  module Rails
    class ServerGenerator::ServerWriter
      def self.write_wrapper_script(config, server_rb_path)
        server_rb = "#{config.server_name}_server.rb"
        wrapper_file_name = "#{config.server_name}_server.sh"
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

      def self.bearer_token
        "Bearer #{ENV["MCP_API_KEY"]}" if ENV["MCP_API_KEY"]
      end
    end
  end
end
