class Channels::MessagesController < ApplicationController
  permitted_params_for :create do
    param :message, required: true do
      param :content, type: :string, description: "Message Content", required: true
    end
  end

  def new; end

  def show; end

  def create
    render json: { mcp_invocation: mcp_invocation?, params: resource_params }, status: :created
  end
end
