# Passkeys (maquina:passkeys)
#
# A passkey is bound to its relying party: rp_id is the domain it belongs to,
# and the browser only offers it on pages from allowed_origins. rp_id can be
# a parent of the origins' host (example.com for https://app.example.com),
# never another domain. Changing rp_id later orphans every saved passkey.
#
# Development and test use localhost; production reads WEBAUTHN_RP_ID and
# WEBAUTHN_ORIGINS (comma-separated), or webauthn: {rp_id:, origins:} in the
# credentials.
webauthn = Rails.application.credentials.webauthn || {}

WebAuthn.configure do |config|
  config.rp_name = ENV.fetch("WEBAUTHN_RP_NAME") { Rails.application.class.module_parent_name.titleize }
  config.rp_id = ENV["WEBAUTHN_RP_ID"] || webauthn[:rp_id] || "localhost"
  config.allowed_origins = Array(ENV["WEBAUTHN_ORIGINS"]&.split(",") || webauthn[:origins] || "http://localhost:3000")
end

# A production app still on localhost would accept no passkey at all. The
# asset build runs in production without the real settings, so it is spared.
if Rails.env.production? && WebAuthn.configuration.rp_id == "localhost" && ENV["SECRET_KEY_BASE_DUMMY"].blank?
  raise "Passkeys: set WEBAUTHN_RP_ID and WEBAUTHN_ORIGINS (see config/initializers/webauthn.rb)"
end
