class NestedParametersController < ApplicationController
  # Test nested parameters
  permitted_params_for :create do
    param :user, required: true do
      param :name, type: :string, required: true
      param :address do
        param :street, type: :string
        param :city, type: :string
      end
    end
  end

  def create
    render json: resource_params
  end
end
