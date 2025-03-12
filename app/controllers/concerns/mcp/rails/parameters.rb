module MCP::Rails::Parameters
  extend ActiveSupport::Concern

  def self.included(base)
    base.extend ClassMethods
    base.class_eval do
      # Initialize instance variables for each class
      @shared_params_defs = {}
      @action_params_defs = {}

      # Define class-level accessors
      def self.shared_params_defs
        @shared_params_defs ||= {}
      end

      def self.action_params_defs
        @action_params_defs ||= {}
      end

      # Optionally, define setters if needed
      def self.shared_params_defs=(value)
        @shared_params_defs = value
      end

      def self.action_params_defs=(value)
        @action_params_defs = value
      end

      # Ensure subclasses get their own fresh instances
      def self.inherited(subclass)
        super
        subclass.instance_variable_set(:@shared_params_defs, {})
        subclass.instance_variable_set(:@action_params_defs, {})
      end
    end

    def mcp_invocation?
      bypass_key = request.headers["X-Bypass-CSRF"]
      stored_key = File.read(MCP::Rails.configuration.bypass_key_path).strip rescue nil
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
      if param[:type] == :array
        if param[:item_type]
          { param[:name] => [] }  # Scalar array
        elsif param[:nested]
          { param[:name] => extract_permitted_keys(param[:nested]) }  # Array of hashes
        else
          raise "Invalid array parameter definition"
        end
      elsif param[:nested]
        { param[:name] => extract_permitted_keys(param[:nested]) }  # Nested object
      else
        param[:name]  # Scalar
      end
    end
  end

  # Builder class for parameter definitions
  class ParamsBuilder
    attr_reader :params

    def initialize
      @params = []
    end

    def param(name, type: nil, item_type: nil, example: nil, required: false, &block)
      param_def = { name: name, required: required }
      if type == :array
        param_def[:type] = :array
        if block_given?
          nested_builder = ParamsBuilder.new
          nested_builder.instance_eval(&block)
          param_def[:nested] = nested_builder.params
        elsif item_type
          param_def[:item_type] = item_type
        else
          raise ArgumentError, "Must provide item_type or a block for array type"
        end
      elsif block_given?
        param_def[:type] = :object
        nested_builder = ParamsBuilder.new
        nested_builder.instance_eval(&block)
        param_def[:nested] = nested_builder.params
      else
        param_def[:type] = type if type
      end
      param_def[:example] = example if example
      @params << param_def
    end
  end
end
