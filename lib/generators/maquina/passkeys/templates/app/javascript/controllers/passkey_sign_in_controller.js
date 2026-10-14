import { Controller } from "@hotwired/stimulus"

// Passkey sign-in (maquina:passkeys).
//
// On connect it starts a conditional request: the browser offers saved
// passkeys in the email field's autofill (autocomplete="username webauthn").
// The button starts a modal request instead. Both use the browser's own JSON
// helpers, so no WebAuthn library is needed. Cancelling the prompt is a
// normal outcome, not an error.
//
// The block is rendered visible and only hidden where passkeys are not
// supported; the view calls refresh on turbo:morph, which puts the server's
// attributes back without reconnecting this controller. A successful sign-in
// loads the next page in full, so it starts with the new session's CSRF token
// and no Turbo snapshot of the signed-out page.
export default class extends Controller {
  static targets = ["button", "error"]
  static values = { challengeUrl: String, url: String, errorMessage: String }

  connect() {
    this.refresh()
    if (supported()) this.#autofill()
  }

  refresh() {
    this.element.hidden = !supported()
  }

  disconnect() {
    this.#abort()
  }

  async signIn() {
    this.buttonTarget.disabled = true
    try {
      await this.#authenticate()
    } finally {
      this.buttonTarget.disabled = false
    }
  }

  async #autofill() {
    if (!(await PublicKeyCredential.isConditionalMediationAvailable?.())) return

    await this.#authenticate("conditional")
  }

  async #authenticate(mediation) {
    this.#abort()
    const abortController = this.abortController = new AbortController()
    if (!mediation) this.#showError(null)

    let credential
    try {
      const options = await post(this.challengeUrlValue)
      if (!options.ok) return this.#showError(options.body.error)

      credential = await navigator.credentials.get({
        publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(options.body),
        signal: abortController.signal,
        ...(mediation && { mediation })
      })
    } catch (error) {
      if (abortController.signal.aborted) return
      if (error.name !== "NotAllowedError") return this.#showError()
      // The modal prompt was cancelled: offer passkeys in autofill again.
      if (!mediation) this.#autofill()
      return
    }

    const result = await post(this.urlValue, { credential: credential.toJSON() })
    if (result.body.redirect_url) return window.location.assign(result.body.redirect_url)

    if (result.status === 404 && result.body.credential_id) {
      // Deleted on the server: ask the passkey provider to drop it too.
      PublicKeyCredential.signalUnknownCredential?.({ rpId: result.body.rp_id, credentialId: result.body.credential_id })
    }
    this.#showError(result.body.error)
    this.#autofill()
  }

  #abort() {
    this.abortController?.abort()
  }

  #showError(message = this.errorMessageValue) {
    this.errorTarget.textContent = message || ""
    this.errorTarget.hidden = !message
  }
}

// JSON POST with the CSRF token; a network failure reads as an empty error.
async function post(url, body) {
  try {
    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/json",
        "X-CSRF-Token": document.querySelector("meta[name=csrf-token]")?.content
      },
      body: body && JSON.stringify(body)
    })
    return { ok: response.ok, status: response.status, body: await response.json().catch(() => ({})) }
  } catch {
    return { ok: false, status: 0, body: {} }
  }
}

function supported() {
  return typeof PublicKeyCredential !== "undefined" &&
    typeof PublicKeyCredential.parseRequestOptionsFromJSON === "function"
}
