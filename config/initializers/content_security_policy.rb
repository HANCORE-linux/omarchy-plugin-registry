# Publisher readmes render as HTML; a restrictive CSP keeps hotlinked images
# (tracking pixels) and any slipped-through markup inert.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self
    policy.img_src     :self, :data
    policy.object_src  :none
    policy.script_src  :self
    policy.style_src   :self, :unsafe_inline
    policy.frame_ancestors :none
  end

  # Importmap's inline <script> tags carry a TRUE per-request nonce — never
  # the session id, which would repeat across every response of a session
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
