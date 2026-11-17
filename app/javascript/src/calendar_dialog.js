import { Modal } from "bootstrap";

// Closes a calendar dialog whose form was saved, without the question about
// unsaved changes that closing it by hand asks. Bootstrap ignores hide() while
// the dialog is still opening, so a dialog left open closes once it has opened.
export function closeSaved(dialog) {
  dialog.dataset.saved = "true";
  Modal.getInstance(dialog)?.hide();
  delete dialog.dataset.saved;
  if (dialog.classList.contains("show"))
    dialog.addEventListener("shown.bs.modal", () => closeSaved(dialog), {
      once: true,
    });
}
