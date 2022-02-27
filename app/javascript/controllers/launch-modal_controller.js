import { Controller } from "stimulus";

export default class extends Controller {
    static targets = ["commentsModal", "quoteModal", "timelineModal"];

    launchCommentsModal(event) {
        let commentsModalController = this.application.getControllerForElementAndIdentifier(
            this.commentsModalTarget,
            "comments-modal"
        );
        console.log(this.commentsModalTarget);
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
}
