require_relative "lib/mcp/rails/version"

Gem::Specification.new do |spec|
  spec.name        = "mcp-rails"
  spec.version     = Mcp::Rails::VERSION
  spec.authors     = [ "Tonksthebear" ]
  spec.homepage    = "https://github.com/Tonksthebear/mcp-rails"
  spec.summary     = "MCP Integration for Rails"
  spec.description = "MCP Integration for Rails"
  spec.license     = "MIT"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/Tonksthebear/mcp-rails"
  spec.metadata["changelog_uri"] = "https://github.com/Tonksthebear/mcp-rails/CHANGELOG.md"

  spec.add_dependency "httparty"
  spec.add_development_dependency "jbuilder"
  spec.add_development_dependency "appraisal"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  spec.add_dependency "rails", ">= 7.2"
end
