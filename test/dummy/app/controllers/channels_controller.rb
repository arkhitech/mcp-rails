class ChannelsController < ApplicationController
  permitted_params_for :create do
    param :channel, required: true do
      param :name, type: :string, example: "Channel Name", required: true
      param :user_ids, type: :array, example: ["1", "2"]
    end
  end

  def index
    @channels = []
    render json: @channels
  end

  def create
    @channel = OpenStruct.new(resource_params)
    render json: @channel, status: :created
  end
end
