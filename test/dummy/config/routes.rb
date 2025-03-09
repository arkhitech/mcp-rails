Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :channels, mcp: true do
    scope module: "channels" do
      resources :messages, mcp: true, shallow: true
    end
  end

  resources :basic_parameters, only: :create, mcp: true
  resources :array_parameters, only: :create, mcp: true
  resources :nested_parameters, only: :create, mcp: true
  resources :shared_parameters, only: :create, mcp: true
end
