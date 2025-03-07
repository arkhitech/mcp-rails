# frozen_string_literal: true

class PostsController < ApplicationController
  permitted_params_for :create do
    param :post, required: true do
      param :title, type: :string, required: true
      param :body_content, type: :string, required: true
    end
  end

  def index
  end

  def create
    puts "GOT CREATE: #{resource_params}"
    render json: { status: :created }
  end

  def update
  end

  def destroy
  end
end
