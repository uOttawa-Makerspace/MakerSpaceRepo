import { Controller } from "@hotwired/stimulus";

// Buttons on a printable page: open the browser's print dialog, or close the
// window the page was opened in.
export default class extends Controller {
  print() {
    window.print();
  }

  close() {
    window.close();
  }
}
