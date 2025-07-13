class ChannelsController < ApplicationController
  tool_description_for :index, "List all channels"

  permitted_params_for :create do
    param :channel, required: true do
      param :name, type: :string, description: "Channel Name", required: true
      param :user_ids, type: :array, item_type: :string, description: [ "1", "2" ]
    end
  end

  def index
    @channels = [ { name: "test", user_ids: [ "1", "2" ] } ]
    render json: @channels
  end

  def show
    respond_to do |format|
      format.json { render json: { name: "json_test", user_ids: [ "1", "2" ] } }
      format.mcp  { render mcp: { name: "mcp_test", user_ids: [ "1", "2" ] } }
    end
  end

  def create
    render json: resource_params, status: :created
  end

  def update
    @instance_var = "instance variable"
  end

  def destroy
    render json: { name: "json fallback test" }
  end
end
