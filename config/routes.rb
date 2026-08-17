Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token

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
  get "index/:publisher/:plugin.json", to: "data_plane#index_file", as: :index_file
  get "dl/:publisher/:plugin/:plugin_file",
    to: "data_plane#tarball", as: :tarball,
    constraints: { plugin_file: /[^\/]+\.tar\.gz/ }
end
