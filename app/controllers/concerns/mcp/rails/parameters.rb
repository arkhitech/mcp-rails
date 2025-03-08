module MCP::Rails::Parameters
  extend ActiveSupport::Concern

  included do
    class_attribute :shared_params_defs, :action_params_defs

    # Use a hook to initialize fresh instances for each class
    self.shared_params_defs = {}
    self.action_params_defs = {}

    # Ensure that inherited classes also get their own copies
    def self.inherited(subclass)
      super
      subclass.shared_params_defs = shared_params_defs.dup
      subclass.action_params_defs = action_params_defs.dup
    end

    def mcp_invocation?
      bypass_key = request.headers["X-Bypass-CSRF"]
      stored_key = File.read(Rails.root.join("tmp", "mcp", "bypass_key.txt")).strip rescue nil
      bypass_key.present? && bypass_key == stored_key
    end
  end

  class_methods do
    # Define shared parameters
    def shared_params(name, &block)
      builder = ParamsBuilder.new
      builder.instance_eval(&block)
      shared_params_defs[name] = builder.params
    end

    # Define parameters for an action
    def permitted_params_for(action, shared: [], &block)
      # Gather shared params
      shared_params = shared.map { |name| shared_params_defs[name] }.flatten.compact
      # Build action-specific params
      action_builder = ParamsBuilder.new
      action_builder.instance_eval(&block) if block_given?
      action_params = action_builder.params
      # Merge, with action-specific overriding shared
      merged_params = merge_params(shared_params, action_params)
      action_params_defs[action.to_sym] = merged_params
    end

    # Get permitted parameters for an action
    def permitted_params(action)
      action_params_defs[action.to_sym] || []
    end

    def mcp_hash(action)
      extract_permitted_mcp_hash(permitted_params(action))
    end

    def extract_permitted_mcp_hash(params_def)
      param_hash = {}
      params_def.each do |param|
        param_hash[param[:name]] = {
          type: param[:type],
          required: param[:required]
        }
        if param[:nested]
          param_hash[param[:name]][:type] = "object"
          param_hash[param[:name]][:properties] = extract_permitted_mcp_hash(param[:nested])
        end
      end
      param_hash
    end

    private

    # Merge shared and action-specific params, with action-specific taking precedence
    def merge_params(shared, specific)
      specific_keys = specific.map { |p| p[:name] }
      shared.reject { |p| specific_keys.include?(p[:name]) } + specific
    end
  end

  # Instance method to get strong parameters, keeping controller clean
  def resource_params
    permitted = extract_permitted_keys(self.class.permitted_params(action_name))
    if (model_hash = permitted.select { |p| p.is_a?(Hash) }) && model_hash.length == 1
      params.require(model_hash.first.keys.first).permit(*model_hash.first.values)
    else
      params.permit(permitted)
    end
  end

  private


  # Helper to extract permitted keys for strong parameters
  def extract_permitted_keys(params_def)
    params_def.map do |param|
      if param[:nested]
        { param[:name] => extract_permitted_keys(param[:nested]) }
      else
        param[:name]
      end
    end
  end

  # Builder class for parameter definitions
  class ParamsBuilder
    attr_reader :params

    def initialize
      @params = []
    end

    def param(name, type: nil, example: nil, required: false, &block)
      param_def = { name: name, required: required }
      param_def[:type] = type if type
      param_def[:example] = example if example
      if block_given?
        param_def[:type] = :object
        nested_builder = ParamsBuilder.new
        nested_builder.instance_eval(&block)
        param_def[:nested] = nested_builder.params
      end
      @params << param_def
    end
  end
end
