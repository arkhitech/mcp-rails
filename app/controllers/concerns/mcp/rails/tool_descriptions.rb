module MCP::Rails::ToolDescriptions
  extend ActiveSupport::Concern

  def self.included(base)
    base.extend ClassMethods
    base.class_eval do
      # Initialize instance variables for each class
      @action_descriptions = {}

      # Define class-level accessors
      def self.action_descriptions
        @action_descriptions ||= {}
      end

      # Optionally, define setters if needed
      def self.action_descriptions=(value)
        @action_descriptions = value
      end

      # Ensure subclasses get their own fresh instances
      def self.inherited(subclass)
        super
        subclass.instance_variable_set(:@action_descriptions, {})
      end
    end
  end

  class_methods do
    # Define description for an action
    def tool_description_for(action, description)
      action_descriptions[action.to_sym] = description
    end

    # Get description for an action
    def tool_description(action)
      action_descriptions[action.to_sym]
    end
  end
end
