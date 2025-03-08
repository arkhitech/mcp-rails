class BasicParametersController < ApplicationController
  permitted_params_for :create do
    param :name, type: :string, required: true
    param :age, type: :integer
 end

  def create
    render json: resource_params
  end
end
