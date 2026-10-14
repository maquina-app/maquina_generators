class PasskeysController < ApplicationController
  include PasskeyChallenge
  include PasskeyReauthentication

  before_action :require_recent_sign_in, only: %i[create destroy]
  before_action :set_passkey, only: %i[update destroy]

  # GET /passkeys
  def index
    @passkeys = Current.user.passkeys.order(:created_at)
  end

  # POST /passkeys
  def create
    challenge = take_passkey_challenge(:registration)
    return render_failure(t("flash.passkeys.challenge_expired")) unless challenge

    credential = WebAuthn::Credential.from_create(passkey_credential_params)
    # Checks the challenge, the origin, the relying party and that the person
    # was verified on the device, not just present.
    credential.verify(challenge, user_verification: true)

    aaguid = credential.response.authenticator_data.aaguid
    Current.user.passkeys.create!(
      credential_id: credential.id,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      transports: credential.response.transports,
      aaguid: aaguid,
      backup_eligible: credential.backup_eligible?,
      backed_up: credential.backed_up?,
      name: Passkey.default_name(aaguid)
    )

    Rails.logger.info "[AUTH] Passkey added for #{Current.user.email_address} from #{request.remote_ip}"
    flash[:notice] = t("flash.passkeys.created")
    render json: {redirect_url: passkeys_url}, status: :created
  rescue WebAuthn::Error, ActiveRecord::RecordInvalid => error
    Rails.logger.info "[AUTH] Passkey registration failed (#{error.class.name.demodulize}) for #{Current.user.email_address}"
    render_failure(t("flash.passkeys.registration_failed"))
  end

  # PATCH /passkeys/:id
  def update
    if @passkey.update(params.expect(passkey: [:name]))
      redirect_to passkeys_path, notice: t("flash.passkeys.updated")
    else
      redirect_to passkeys_path, alert: @passkey.errors.full_messages.to_sentence
    end
  end

  # DELETE /passkeys/:id
  def destroy
    @passkey.destroy
    Rails.logger.info "[AUTH] Passkey removed for #{Current.user.email_address} from #{request.remote_ip}"
    redirect_to passkeys_path, notice: t("flash.passkeys.destroyed"), status: :see_other
  end

  private

  def set_passkey
    @passkey = Current.user.passkeys.find(params[:id])
  end

  def render_failure(message)
    render json: {error: message}, status: :unprocessable_entity
  end
end
