import { Controller } from "@hotwired/stimulus"

// Passkey ceremonies: registration (settings) and authentication (sign-in).
// Uses the WebAuthn JSON serialization APIs; both flows fetch options from the
// server, run the browser ceremony, and post the credential back.
export default class extends Controller {
  static values = { optionsUrl: String, verifyUrl: String, nickname: String }
  static targets = ["error"]

  async register() {
    try {
      const options = await this.fetchOptions()
      const publicKey = PublicKeyCredential.parseCreationOptionsFromJSON
        ? PublicKeyCredential.parseCreationOptionsFromJSON(options)
        : this.manualParseCreation(options)
      const credential = await navigator.credentials.create({ publicKey })
      await this.verify({ credential: JSON.stringify(this.serializeCredential(credential)) })
      window.location.reload()
    } catch (error) {
      this.showError(error)
    }
  }

  async authenticate() {
    try {
      const options = await this.fetchOptions()
      const publicKey = PublicKeyCredential.parseRequestOptionsFromJSON
        ? PublicKeyCredential.parseRequestOptionsFromJSON(options)
        : this.manualParseRequest(options)
      const credential = await navigator.credentials.get({ publicKey })
      const result = await this.verify({ credential: JSON.stringify(this.serializeCredential(credential)) })
      window.location = result.redirect || "/"
    } catch (error) {
      this.showError(error)
    }
  }

  async fetchOptions() {
    const response = await fetch(this.optionsUrlValue, { method: "POST", headers: this.headers() })
    this.followNonJsonRedirect(response)
    if (!response.ok) throw new Error("Could not start the passkey ceremony.")
    return response.json()
  }

  async verify(body) {
    const response = await fetch(this.verifyUrlValue, {
      method: "POST",
      headers: { ...this.headers(), "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ ...body, nickname: this.nicknameValue || "" })
    })
    this.followNonJsonRedirect(response)
    const json = await response.json()
    if (!response.ok) throw new Error(json.error || "Passkey verification failed.")
    return json
  }

  // A redirect to an HTML page (e.g. the step-up gate) means the server wants
  // the user somewhere else — navigate there instead of choking on non-JSON.
  followNonJsonRedirect(response) {
    const isJson = (response.headers.get("Content-Type") || "").includes("json")
    if (response.redirected && !isJson) {
      window.location = response.url
      throw new Error("Redirecting…")
    }
  }

  headers() {
    const token = document.querySelector('meta[name="csrf-token"]')?.content
    return token ? { "X-CSRF-Token": token } : {}
  }

  showError(error) {
    if (this.hasErrorTarget) this.errorTarget.textContent = error.message
    else alert(error.message)
  }

  // Fallbacks for browsers without the JSON parsing helpers
  manualParseCreation(options) {
    options.challenge = this.b64ToBuf(options.challenge)
    options.user.id = this.b64ToBuf(options.user.id)
    ;(options.excludeCredentials || []).forEach(c => { c.id = this.b64ToBuf(c.id) })
    return options
  }

  manualParseRequest(options) {
    options.challenge = this.b64ToBuf(options.challenge)
    ;(options.allowCredentials || []).forEach(c => { c.id = this.b64ToBuf(c.id) })
    return options
  }

  b64ToBuf(value) {
    const padded = value.replace(/-/g, "+").replace(/_/g, "/")
    const raw = atob(padded + "=".repeat((4 - (padded.length % 4)) % 4))
    return Uint8Array.from(raw, c => c.charCodeAt(0)).buffer
  }

  bufToB64url(buffer) {
    const bytes = new Uint8Array(buffer)
    let raw = ""
    for (const b of bytes) raw += String.fromCharCode(b)
    return btoa(raw).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "")
  }

  // Credential attributes aren't enumerable, so JSON.stringify(credential)
  // would produce {} — build the wire format explicitly when toJSON is absent.
  serializeCredential(credential) {
    if (credential.toJSON) return credential.toJSON()
    const response = credential.response
    const out = {
      id: credential.id,
      rawId: this.bufToB64url(credential.rawId),
      type: credential.type,
      authenticatorAttachment: credential.authenticatorAttachment,
      clientExtensionResults: credential.getClientExtensionResults ? credential.getClientExtensionResults() : {},
      response: { clientDataJSON: this.bufToB64url(response.clientDataJSON) }
    }
    if (response.attestationObject) {
      out.response.attestationObject = this.bufToB64url(response.attestationObject)
      if (response.getTransports) out.response.transports = response.getTransports()
    } else {
      out.response.authenticatorData = this.bufToB64url(response.authenticatorData)
      out.response.signature = this.bufToB64url(response.signature)
      out.response.userHandle = response.userHandle ? this.bufToB64url(response.userHandle) : null
    }
    return out
  }
}
