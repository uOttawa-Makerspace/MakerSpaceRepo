import { Controller } from "stimulus";

export default class extends Controller {
    static targets = ["commentsModal", "quoteModal", "timelineModal", "completedEmailModal", "declineModal"];

    launchCommentsModal(event) {
        let commentsModalController = this.application.getControllerForElementAndIdentifier(
            this.commentsModalTarget,
            "comments-modal"
        );
        commentsModalController.setCoHostContent(event.currentTarget.dataset);
        commentsModalController.open();
    }

    launchQuoteModal(event) {
        let quoteModalController = this.application.getControllerForElementAndIdentifier(
            this.quoteModalTarget,
            "quote-modal"
        );
        quoteModalController.setCoHostContent(event.currentTarget.dataset);
        quoteModalController.open();
    }

    launchTimelineModal(event) {
        let timelineModalController = this.application.getControllerForElementAndIdentifier(
            this.timelineModalTarget,
            "timeline-modal"
        );
        timelineModalController.setCoHostContent(event.currentTarget.dataset);
        timelineModalController.open();
    }

    launchCompletedEmailModal(event) {
        let completedEmailModalController = this.application.getControllerForElementAndIdentifier(
            this.completedEmailModalTarget,
            "completed-email-modal"
        );
        completedEmailModalController.setCoHostContent(event.currentTarget.dataset);
        completedEmailModalController.open();
    }

    launchDeclineModal(event) {
        let declineModalController = this.application.getControllerForElementAndIdentifier(
            this.declineModalTarget,
            "decline-modal"
        );
        declineModalController.setCoHostContent(event.currentTarget.dataset);
        declineModalController.open();
    }
}
