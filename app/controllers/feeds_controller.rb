class FeedsController < ApplicationController
  allow_unauthenticated_access

  # Atom feed of the most recent releases across the registry — one entry per
  # published version, newest first.
  def show
    @versions = PluginVersion.published.where.not(published_at: nil)
      .includes(plugin: :publisher)
      .order(published_at: :desc).limit(50)
    expires_in 30.minutes, public: true
    render formats: :atom, layout: false
  end
end
