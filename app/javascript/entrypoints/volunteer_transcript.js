// The volunteer transcript is a standalone printable page (no app layout), so
// it starts Stimulus with only the controller its print buttons use.
import { Application } from "@hotwired/stimulus";
import PrintWindow from "../controllers/print_window_controller.js";

Application.start().register("print-window", PrintWindow);

// The page script has run. Specs wait on this flag before their first click.
document.documentElement.dataset.appJsReady = "true";
