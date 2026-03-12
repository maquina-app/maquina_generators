import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["source", "successTemplate"]
  static classes = ["success"]

  async copy() {
    if (!navigator.clipboard) return

    const text = this.sourceTarget.textContent || this.sourceTarget.value

    try {
      await navigator.clipboard.writeText(text.trim())
      this.#showSuccess()
      this.dispatch("copied", { detail: { text: text.trim() } })
    } catch {
      // Silently fail if clipboard access is denied
    }
  }

  #showSuccess() {
    if (!this.hasSuccessTemplateTarget) return

    const button = this.element.querySelector("[data-action*='clipboard#copy']")
    if (!button) return

    const originalHTML = button.innerHTML
    button.innerHTML = this.successTemplateTarget.innerHTML
    if (this.hasSuccessClass) button.classList.add(...this.successClasses)

    setTimeout(() => {
      button.innerHTML = originalHTML
      if (this.hasSuccessClass) button.classList.remove(...this.successClasses)
    }, 2000)
  }
}
