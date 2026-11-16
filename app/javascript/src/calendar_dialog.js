import { Modal } from "bootstrap";

// Closes a calendar dialog whose form was saved, without the question about
// unsaved changes that closing it by hand asks.
export function closeSaved(dialog) {
  dialog.dataset.saved = "true";
  Modal.getInstance(dialog)?.hide();
  delete dialog.dataset.saved;
}
