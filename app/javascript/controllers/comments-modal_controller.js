import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static targets = ['id', 'comments'];

    setCoHostContent(data) {
        this.idTarget.innerHTML = data.id;
        this.commentsTarget.innerHTML = data.comments.replace(/\n/g,'<br />');
    }

    open() {
        document.body.classList.add("modal-open");
        this.element.setAttribute("style", "display: block;");
        this.element.classList.add("show");

        const modalBackdrop = document.createElement("div")
        modalBackdrop.classList.add("modal-backdrop");
        modalBackdrop.classList.add("fade");
        modalBackdrop.classList.add("show");
        modalBackdrop.id = "modal-backdrop";
        document.body.append(modalBackdrop);
    }

    close() {
        document.body.classList.remove("modal-open");
        this.element.removeAttribute("style");
        this.element.classList.remove("show");
        document.getElementsByClassName("modal-backdrop")[0].remove();
    }
}