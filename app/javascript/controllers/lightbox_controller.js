import { Controller } from "@hotwired/stimulus"

// Click-to-enlarge for plugin previews using the native <dialog> element —
// Escape and backdrop clicks close it, focus returns to the trigger for free.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }

  // A click on the dialog element itself (not its children) is the backdrop.
  backdropClose(event) {
    if (event.target === this.dialogTarget) this.close()
  }
}
