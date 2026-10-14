class Session::PasskeysController < ApplicationController
  include PasskeyChallenge

  allow_unauthenticated_access
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { render json: {error: t("flash.general.rate_limited")}, status: :too_many_requests }

  # POST /session/passkey
  def create
    challenge = take_passkey_challenge(:authentication)
    return render_failure(t("flash.passkeys.challenge_expired")) unless challenge

    credential = WebAuthn::Credential.from_get(passkey_credential_params)
    passkey = Passkey.includes(:user).find_by(credential_id: credential.id)

    # Deleted here but still saved on the device: the browser can be told to
    # forget it (PublicKeyCredential.signalUnknownCredential).
    unless passkey
      Rails.logger.info "[AUTH] Passkey sign-in with an unknown credential from #{request.remote_ip}"
      render json: {error: t("flash.passkeys.unknown"), credential_id: credential.id, rp_id: WebAuthn.configuration.rp_id},
        status: :not_found
      return
    end

    user = passkey.user
    if user.blocked? || credential.user_handle != user.webauthn_id
      Rails.logger.info "[AUTH] Passkey sign-in refused for #{user.email_address} from #{request.remote_ip}"
      return render_failure(t("flash.passkeys.failed"))
    end

    # Checks the challenge, the origin, the signature with the stored public
    # key, user verification (Face ID, fingerprint, device PIN) and that the
    # signature counter moved forward.
    credential.verify(challenge, public_key: passkey.public_key, sign_count: passkey.sign_count, user_verification: true)
    passkey.record_use!(credential.sign_count)

    Rails.logger.info "[AUTH] Successful passkey login for #{user.email_address} from #{request.remote_ip}"
    start_new_session_for(user)
    flash[:notice] = t("flash.sessions.create.success")
    render json: {redirect_url: after_authentication_url}
  rescue WebAuthn::SignCountVerificationError
    # A valid signature with a counter that went backwards: possibly a cloned
    # authenticator. Synced passkeys always report 0 and never land here.
    Rails.logger.warn "[AUTH] Passkey sign count went backwards for #{passkey.user.email_address} from #{request.remote_ip}"
    render_failure(t("flash.passkeys.failed"))
  rescue WebAuthn::Error => error
    Rails.logger.info "[AUTH] Passkey sign-in failed (#{error.class.name.demodulize}) from #{request.remote_ip}"
    render_failure(t("flash.passkeys.failed"))
  end

  private

  def render_failure(message)
    render json: {error: message}, status: :unprocessable_entity
  end
end
