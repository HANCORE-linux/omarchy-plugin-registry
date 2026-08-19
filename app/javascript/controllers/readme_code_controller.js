import { Controller } from "@hotwired/stimulus"
import { copyText } from "lib/clipboard"

// Publisher readmes are arbitrary markdown — every fenced code block gets a
// floating copy control (Lucide copy/check), injected at connect so the
// server-rendered markdown stays untouched.
const ICONS = `
  <svg class="copy-button__copy" viewBox="0 0 24 24" fill="none" stroke="currentColor"
       stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <rect width="14" height="14" x="8" y="8" rx="2" ry="2"/>
    <path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/>
  </svg>
  <svg class="copy-button__check" viewBox="0 0 24 24" fill="none" stroke="currentColor"
       stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">
    <path d="M20 6 9 17l-5-5"/>
  </svg>`

export default class extends Controller {
  connect() {
    this.element.querySelectorAll("pre").forEach((pre) => {
      if (pre.parentElement.classList.contains("codeblock")) return
      const wrapper = document.createElement("div")
      wrapper.className = "codeblock"
      pre.replaceWith(wrapper)
      wrapper.appendChild(pre)

      const button = document.createElement("button")
      button.type = "button"
      button.className = "copy-button copy-button--floating"
      button.setAttribute("aria-label", "Copy code")
      button.title = "Copy code"
      button.innerHTML = ICONS
      button.addEventListener("click", async () => {
        await copyText(pre.innerText.trim())
        button.classList.add("copy-button--done")
        clearTimeout(button.dataset.timer)
        button.dataset.timer = setTimeout(() => button.classList.remove("copy-button--done"), 1600)
      })
      wrapper.appendChild(button)
    })
  }
}
