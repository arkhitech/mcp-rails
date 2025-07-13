class SharedParametersController < ApplicationController
  # Test shared parameters
  shared_params :contact_info do
    param :email, type: :string, description: "user@example.com"
    param :phone, type: :string
  end

  permitted_params_for :create, shared: [ :contact_info ] do
    param :name, type: :string, required: true
  end

  def create
    render json: resource_params
  end
end
