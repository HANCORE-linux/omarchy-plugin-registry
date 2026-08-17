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
    resources :passkeys, only: %i[create destroy] do
      post :options, on: :collection
    end
  end
  post "session/passkey/options", to: "passkey_sessions#options"
  post "session/passkey", to: "passkey_sessions#create"

  # Step-up verification for credential-minting actions
  get "step_up", to: "step_up#show"
  post "step_up", to: "step_up#create"
  post "step_up/passkey/options", to: "step_up#passkey_options", as: :step_up_passkey_options
  post "step_up/passkey", to: "step_up#passkey_verify", as: :step_up_passkey_verify
  resources :tokens, only: %i[create destroy]
  resources :trusted_publishers, only: %i[create destroy]
  resources :orgs, only: %i[new create] do
    member do
      post :add_member
      post :remove_member
    end
  end

  # Public directory
  get "plugins/:publisher/:name", to: "plugins#show", as: :plugin
  post "plugins/:publisher/:name/rating", to: "ratings#create", as: :plugin_rating
  post "plugins/:publisher/:name/comments", to: "comments#create", as: :plugin_comments
  resources :comments, only: :destroy
  resources :reports, only: :create
  get "publishers/:name", to: "publishers#show", as: :publisher
  get "publishers/:name/claim", to: "claims#show", as: :claim
  post "publishers/:name/claim", to: "claims#verify", as: :verify_claim
  get "governance", to: "pages#governance"
  get "publishing", to: "pages#publishing"
  get "audit", to: "audit_log#index", as: :audit_log

  namespace :admin do
    root "dashboard#show"
    resources :versions, only: :show do
      member do
        get :download_tarball
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
    resources :reports, only: [] do
      member do
        post :resolve
      end
    end
    resources :comments, only: [] do
      member do
        post :hide
      end
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check

  # --- Publish API (control plane) ---
  namespace :api do
    namespace :v1 do
      post "plugins/:publisher/:plugin/versions", to: "versions#create",
        constraints: { publisher: %r{[^/]+}, plugin: %r{[^/]+} }
      post "device/code", to: "device#code"
      post "device/token", to: "device#token"
      post "trusted/exchange", to: "trusted#exchange"
    end
  end

  # Browser side of the CLI device flow
  get "device", to: "device#show"
  post "device/approve", to: "device#approve", as: :approve_device

  # --- Static data plane (CDN origin) ---
  # .sig routes serve real sibling objects so a dumb CDN/object store works;
  # ?sig=1 remains a Rails-only convenience. Signature routes come FIRST and
  # every route is format: false, so "/x.json.sig" can never fall through to
  # the unsigned route via an implicit format suffix.
  get "config.json.sig", to: "data_plane#config", defaults: { sig: "1" }, format: false
  get "config.json", to: "data_plane#config", format: false
  get "all.json.sig", to: "data_plane#all", defaults: { sig: "1" }, format: false
  get "all.json", to: "data_plane#all", format: false
  get "revocations.json.sig", to: "data_plane#revocations", defaults: { sig: "1" }, format: false
  get "revocations.json", to: "data_plane#revocations", format: false
  get "signing-key.pub", to: "data_plane#signing_key", format: false
  get "index/:publisher/:plugin.json.sig", to: "data_plane#index_file", defaults: { sig: "1" }, format: false
  get "index/:publisher/:plugin.json", to: "data_plane#index_file", as: :index_file, format: false
  get "dl/:publisher/:plugin/:plugin_file",
    to: "data_plane#tarball", as: :tarball,
    constraints: { plugin_file: /[^\/]+\.tar\.gz/ }
end
