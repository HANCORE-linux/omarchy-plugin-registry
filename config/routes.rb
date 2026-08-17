Rails.application.routes.draw do
  root "home#index"

  # Passwordless auth (Cortex/Herald flow): email -> one-time code -> session
  resource :session, only: %i[new create destroy] do
    get :verify
    post :authenticate
  end
  get "onboarding", to: "onboarding#show"
  post "onboarding", to: "onboarding#create"

  resource :dashboard, only: :show, controller: "dashboard"
  namespace :settings do
    resource :two_factor, only: %i[show update], controller: "two_factor"
  end
  resources :tokens, only: %i[create destroy]
  resources :orgs, only: %i[new create] do
    member do
      post :add_member
    end
  end

  # Public directory
  get "plugins/:publisher/:name", to: "plugins#show", as: :plugin
  get "publishers/:name", to: "publishers#show", as: :publisher
  get "governance", to: "pages#governance"
  get "publishing", to: "pages#publishing"
  get "audit", to: "audit_log#index", as: :audit_log

  namespace :admin do
    root "dashboard#show"
    resources :versions, only: [] do
      member do
        post :approve
        post :reject
        post :quarantine
        post :yank
        post :revoke
      end
    end
    resources :plugins, only: [] do
      member do
        post :security_hold
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # --- Publish API (control plane) ---
  namespace :api do
    namespace :v1 do
      post "plugins/:publisher/:plugin/versions", to: "versions#create",
        constraints: { publisher: %r{[^/]+}, plugin: %r{[^/]+} }
    end
  end

  # --- Static data plane (CDN origin) ---
  get "config.json", to: "data_plane#config"
  get "all.json", to: "data_plane#all"
  get "revocations.json", to: "data_plane#revocations"
  get "signing-key.pub", to: "data_plane#signing_key"
  get "index/:publisher/:plugin.json", to: "data_plane#index_file", as: :index_file
  get "dl/:publisher/:plugin/:plugin_file",
    to: "data_plane#tarball", as: :tarball,
    constraints: { plugin_file: /[^\/]+\.tar\.gz/ }
end
