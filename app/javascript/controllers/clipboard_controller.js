import { Controller } from "@hotwired/stimulus"

// One-click copy for install commands and one-time secrets. The exact text
// travels in a value (never scraped from the DOM, so prompts and truncation
// can't corrupt it); the button confirms inline and reverts.
export default class extends Controller {
  static targets = ["button"]
  static values = { text: String }

  async copy() {
    const text = this.textValue
    try {
      await navigator.clipboard.writeText(text)
    } catch {
      // Clipboard API can be unavailable (permissions, older engines) —
      // fall back to the selection-based path
      const scratch = document.createElement("textarea")
      scratch.value = text
      scratch.setAttribute("readonly", "")
      scratch.style.position = "absolute"
      scratch.style.left = "-9999px"
      document.body.appendChild(scratch)
      scratch.select()
      document.execCommand("copy")
      scratch.remove()
    }
    this.confirm()
  }

  confirm() {
    this.buttonTarget.classList.add("copy-button--done")
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.buttonTarget.classList.remove("copy-button--done"), 1600)
  }
}
