import { Controller } from "stimulus";

export default class extends Controller {
    static targets = ['id'];
    id = null;

    setCoHostContent(data) {
        this.idTarget.innerHTML = data.id;
        this.id = data.id;
    }

    async open() {
        await fetch(`/job_orders/${this.id}/timeline_modal`)
            .then((r) => r.text())
            .then((html) => {
                const fragment = document
                    .createRange()
                    .createContextualFragment(html);
                document.getElementById("timeline-body").appendChild(fragment);
            });
        document.body.classList.add("modal-open");
        this.element.setAttribute("style", "display: block;");
        this.element.classList.add("show");
        document.body.innerHTML += '<div id="modal-backdrop" class="modal-backdrop fade show"></div>';
    }

    close() {
        document.body.classList.remove("modal-open");
        this.element.removeAttribute("style");
        this.element.classList.remove("show");
        document.getElementsByClassName("modal-backdrop")[0].remove();
        document.getElementById("timeline-body").removeChild(document.getElementById("timeline-modal-rendered"));
    }
}