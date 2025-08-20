import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["jobOrderCommentsModal"];

  launchJobOrderCommentsModal(event) {
    let jobOrderCommentsModalController =
      this.application.getControllerForElementAndIdentifier(
        this.jobOrderCommentsModalTarget,
        "job-order-comments-modal",
      );
    jobOrderCommentsModalController.setCoHostContent(
      event.currentTarget.dataset,
    );
    jobOrderCommentsModalController.open();
  }
}
