class Channels::MessagesController < ApplicationController
  permitted_params_for :create do
    param :message, required: true do
      param :content, type: :string, example: "Message Content", required: true
    end
  end

  def create
    @message = OpenStruct.new(resource_params)
    render json: @message, status: :created
  end
end
