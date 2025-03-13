module MCP::Rails::ErrorHandling
  extend ActiveSupport::Concern

  included do
    rescue_from StandardError, with: :handle_mcp_error
  end

  private

  def handle_mcp_error(exception)
    if mcp_request?
      render json: {
        status: "error",
        message: exception.message,
        code: exception.class.name.underscore
      }, status: :unprocessable_entity
    else
      raise exception # Re-raise the exception for non-mcp requests
    end
  end

  def mcp_request?
    request.format == :mcp || request.accept.include?("application/vnd.mcp+json")
  end
end
