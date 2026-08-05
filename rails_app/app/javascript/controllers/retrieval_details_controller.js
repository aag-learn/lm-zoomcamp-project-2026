import { Controller } from "@hotwired/stimulus"

// Opens/closes the "retrieval details" popup on an assistant message --
// an on-demand inspector for what SearchAnsibleDocs actually found, shown
// unfiltered regardless of relevance. See hide-tool-orchestration-messages.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
