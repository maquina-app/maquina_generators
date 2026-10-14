class PasskeyChallengesController < ApplicationController
  include PasskeyChallenge
  include PasskeyReauthentication

  before_action :require_recent_sign_in

  # POST /passkey_challenge
  #
  # Options for navigator.credentials.create(). A discoverable credential
  # (resident key) is what makes it a passkey: the device keeps the account,
  # so sign-in needs no email. The user's existing passkeys are excluded so the
  # same authenticator is not registered twice.
  def create
    user = Current.user
    options = WebAuthn::Credential.options_for_create(
      user: {id: user.webauthn_id, name: user.email_address, display_name: user.name.presence || user.email_address},
      exclude: user.passkeys.pluck(:credential_id),
      authenticator_selection: {resident_key: "required", user_verification: "required"}
    )
    store_passkey_challenge(:registration, options.challenge)

    render json: options
  end
end
