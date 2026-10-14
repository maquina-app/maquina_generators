class Session::PasskeyChallengesController < ApplicationController
  include PasskeyChallenge

  allow_unauthenticated_access

  # POST /session/passkey_challenge
  #
  # Options for navigator.credentials.get(). No allowCredentials: the browser
  # offers every passkey it holds for this site, so nobody types an email and
  # the response says nothing about which accounts exist. It is a POST so a
  # Turbo-cached page never reuses a challenge.
  def create
    options = WebAuthn::Credential.options_for_get(user_verification: "required")
    store_passkey_challenge(:authentication, options.challenge)

    render json: options
  end
end
