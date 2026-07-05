# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  if Rails.env.production?
    Sidekiq::Web.use Rack::Auth::Basic do |username, password|
      ActiveSupport::SecurityUtils.secure_compare(username, ENV.fetch("SIDEKIQ_USERNAME", "admin")) &
        ActiveSupport::SecurityUtils.secure_compare(password, ENV.fetch("SIDEKIQ_PASSWORD", ""))
    end
  end
  mount Sidekiq::Web => "/sidekiq"
  devise_for :users,
             path: "auth",
             path_names: {
               sign_in: "login",
               sign_out: "logout",
               registration: "signup",
             },
             controllers: {
               sessions: "auth/sessions",
               registrations: "auth/registrations",
               omniauth_callbacks: "auth/omniauth_callbacks",
             }

  namespace :auth do
    get "me", to: "users#me"
    delete "spotify", to: "spotify#destroy"
  end

  namespace :api do
    namespace :v1 do
      resource :library, only: [] do
        get :status
        post :fetch_playlists
        post :sync
      end
      resources :playlists, only: %i[index update]
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
