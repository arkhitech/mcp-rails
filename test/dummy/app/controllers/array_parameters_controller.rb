class ArrayParametersController < ApplicationController
  permitted_params_for :create do
    param :tags, type: :array, item_type: :string, description: [ "tag1", "tag2" ]
    param :items, required: true do
      param :ids, type: :array, item_type: :integer, required: true
      param :names, type: :array, item_type: :string, description: [ "item1", "item2" ]
    end
    param :options, type: :array do
      param :name, type: :string, description: "Option Name"
      param :enabled, type: :boolean, description: true
    end
  end

  def create
    render json: resource_params
  end
end
