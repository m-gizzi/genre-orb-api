# frozen_string_literal: true

require "sidekiq/web"

Rails.application.routes.draw do
  if Rails.env.production?
    Sidekiq::Web.use Rack::Auth::Basic do |username, password|
      expected_username = ENV.fetch("SIDEKIQ_USERNAME", "admin")
      expected_password = ENV["SIDEKIQ_PASSWORD"].to_s

      next false if expected_password.blank?

      ActiveSupport::SecurityUtils.secure_compare(username, expected_username) &
        ActiveSupport::SecurityUtils.secure_compare(password, expected_password)
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
      resources :playlists, only: %i[index show update] do
        get :tracks, on: :member
      end
      resources :artists, only: %i[index show] do
        collection do
          get :sync_status
          post :sync
        end
      end
      resources :albums, only: %i[index show]
      resources :genres, only: %i[index show]
      resources :tracks, only: %i[index show]
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
