import { Controller } from "stimulus";

export default class extends Controller {
    static targets = ["modal"];

    launchCommentsModal(event) {
        let modalController = this.application.getControllerForElementAndIdentifier(
            this.modalTarget,
            "comments-modal"
        );
        modalController.setCoHostContent(event.currentTarget.dataset);
        modalController.open();
    }
}
