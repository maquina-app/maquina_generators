import { Controller } from "@hotwired/stimulus"

// Passkey registration and upkeep (maquina:passkeys).
//
// The button creates a passkey with the browser's own JSON helpers. On
// connect the page tells the passkey provider which passkeys this account
// still has and how it is named, so one removed here disappears from the
// device's list too. Both signals are skipped where unsupported.
//
// The button is rendered visible and only hidden where passkeys are not
// supported. A Turbo morph puts the server's attributes back without
// reconnecting this controller, so the view calls refresh on turbo:morph.
export default class extends Controller {
  static targets = ["button", "error", "unsupported"]
  static values = {
    challengeUrl: String,
    url: String,
    errorMessage: String,
    duplicateMessage: String,
    rpId: String,
    userId: String,
    userName: String,
    displayName: String,
    credentialIds: Array
  }

  connect() {
    this.refresh()
    if (supported()) this.#signalAccountState()
  }

  refresh() {
    this.buttonTarget.hidden = !supported()
    this.unsupportedTarget.hidden = supported()
  }

  async register() {
    this.buttonTarget.disabled = true
    this.#showError(null)

    try {
      const options = await post(this.challengeUrlValue)
      // Sign in again first: a full load, so the new session gets a fresh page.
      if (options.body.redirect_url) return window.location.assign(options.body.redirect_url)
      if (!options.ok) return this.#showError(options.body.error)

      let credential
      try {
        credential = await navigator.credentials.create({
          publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(options.body)
        })
      } catch (error) {
        // Cancelled, or this device already holds a passkey for the account.
        if (error.name === "NotAllowedError") return
        if (error.name === "InvalidStateError") return this.#showError(this.duplicateMessageValue)
        return this.#showError()
      }

      const result = await post(this.urlValue, { credential: credential.toJSON() })
      if (result.body.redirect_url) return visit(result.body.redirect_url)
      this.#showError(result.body.error)
    } finally {
      this.buttonTarget.disabled = false
    }
  }

  #signalAccountState() {
    const { rpIdValue: rpId, userIdValue: userId } = this

    PublicKeyCredential.signalAllAcceptedCredentials?.({
      rpId, userId, allAcceptedCredentialIds: this.credentialIdsValue
    }).catch(() => {})
    PublicKeyCredential.signalCurrentUserDetails?.({
      rpId, userId, name: this.userNameValue, displayName: this.displayNameValue
    }).catch(() => {})
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

function visit(url) {
  window.Turbo ? window.Turbo.visit(url) : window.location.assign(url)
}

function supported() {
  return typeof PublicKeyCredential !== "undefined" &&
    typeof PublicKeyCredential.parseCreationOptionsFromJSON === "function"
}
