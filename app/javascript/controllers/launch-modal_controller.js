import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = [
    "commentsModal",
    "quoteModal",
    "timelineModal",
    "completedEmailModal",
    "declineModal",
    "orderItemModal",
    "approveOrderItemModal",
    "revokeOrderItemModal",
    "proficientProjectModal",
  ];

  launchCommentsModal(event) {
    let commentsModalController =
      this.application.getControllerForElementAndIdentifier(
        this.commentsModalTarget,
        "comments-modal"
      );
    commentsModalController.setCoHostContent(event.currentTarget.dataset);
    commentsModalController.open();
  }

  launchQuoteModal(event) {
    let quoteModalController =
      this.application.getControllerForElementAndIdentifier(
        this.quoteModalTarget,
        "quote-modal"
      );
    quoteModalController.setCoHostContent(event.currentTarget.dataset);
    quoteModalController.open();
  }

  launchTimelineModal(event) {
    let timelineModalController =
      this.application.getControllerForElementAndIdentifier(
        this.timelineModalTarget,
        "timeline-modal"
      );
    timelineModalController.setCoHostContent(event.currentTarget.dataset);
    timelineModalController.open();
  }

  launchCompletedEmailModal(event) {
    let completedEmailModalController =
      this.application.getControllerForElementAndIdentifier(
        this.completedEmailModalTarget,
        "completed-email-modal"
      );
    completedEmailModalController.setCoHostContent(event.currentTarget.dataset);
    completedEmailModalController.open();
  }

  launchDeclineModal(event) {
    let declineModalController =
      this.application.getControllerForElementAndIdentifier(
        this.declineModalTarget,
        "decline-modal"
      );
    declineModalController.setCoHostContent(event.currentTarget.dataset);
    declineModalController.open();
  }

  launchOrderItemModal(event) {
    let orderItemModalController =
      this.application.getControllerForElementAndIdentifier(
        this.orderItemModalTarget,
        "order-item-modal"
      );
    orderItemModalController.setCoHostContent(event.currentTarget.dataset);
    orderItemModalController.open();
  }

  launchApproveOrderItemModal(event) {
    let approveOrderItemModalController =
      this.application.getControllerForElementAndIdentifier(
        this.approveOrderItemModalTarget,
        "approve-order-item-modal"
      );
    approveOrderItemModalController.setCoHostContent(
      event.currentTarget.dataset
    );
    approveOrderItemModalController.open();
  }

  launchRevokeOrderItemModal(event) {
    let revokeOrderItemModalController =
      this.application.getControllerForElementAndIdentifier(
        this.revokeOrderItemModalTarget,
        "revoke-order-item-modal"
      );
    revokeOrderItemModalController.setCoHostContent(
      event.currentTarget.dataset
    );
    revokeOrderItemModalController.open();
  }

  launchProficientProjectModal(event) {
    let proficientProjectModalController =
      this.application.getControllerForElementAndIdentifier(
        this.proficientProjectModalTarget,
        "proficient-project-modal"
      );
    proficientProjectModalController.setCoHostContent(
      event.currentTarget.dataset
    );
    proficientProjectModalController.open();
  }
}
