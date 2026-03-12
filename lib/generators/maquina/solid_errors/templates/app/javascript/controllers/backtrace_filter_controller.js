import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["line", "button"]
  static values = { filter: { type: String, default: "application" } }

  connect() {
    this.filterValueChanged()
  }

  setFilter(event) {
    this.filterValue = event.currentTarget.dataset.filter
  }

  filterValueChanged() {
    this.lineTargets.forEach((line) => {
      const type = line.dataset.backtraceType
      const visible = this.filterValue === "all" || type === this.filterValue
      line.hidden = !visible
    })

    this.buttonTargets.forEach((button) => {
      const isActive = button.dataset.filter === this.filterValue
      button.dataset.variant = isActive ? "secondary" : "outline"
    })
  }
}
