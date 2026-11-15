import { Tab } from "bootstrap";
import { AccessorController } from "../src/accessor_controller.js";

// The booking page opens on the tab its address names: the anchor's tab, else
// the admin tab scrolled to the table of a page parameter, else Book Room. An
// anchor that names no tab leaves the tabs as they are. Bootstrap's tab plugin
// shows the opening tab, as it shows a clicked one (classes, aria-selected, fade).
const TABLE_OF_PAGE_PARAMETER = {
  pending_page: "pendingBody",
  approved_page: "approvedBody",
  denied_page: "declinedBody",
  old_pending_page: "pastPendingBody",
  old_approved_page: "pastApprovedBody",
  old_denied_page: "pastDeclinedBody",
};

function tableOfPageParameter(search) {
  const params = new URLSearchParams(search);
  return Object.entries(TABLE_OF_PAGE_PARAMETER).find(([key]) =>
    params.has(key),
  )?.[1];
}

export default class extends AccessorController {
  static targets = ["tab"];

  connect() {
    const anchor = window.location.hash.replace("#", "");
    const table = tableOfPageParameter(window.location.search);
    if (anchor) this.open(anchor);
    else if (table) this.open("booking-admin-tab", table);
    else this.open("booking-calendar-tab");
  }

  open(id, table = null) {
    const tab = this.tabTargets.find((each) => each.id === `${id}-btn`);
    if (!tab) return;
    Tab.getOrCreateInstance(tab).show();
    if (table) this.scrollToTable(table);
  }

  // The table's top, 7rem below the window's top so the page header does not cover it.
  scrollToTable(id) {
    const table = this.element.querySelector(`#${id}`);
    if (!table) return;
    table.scrollIntoView({
      behavior: "smooth",
      block: "start",
      inline: "nearest",
    });
    const root = this.element.ownerDocument.documentElement;
    window.scrollBy(0, -7 * parseFloat(getComputedStyle(root).fontSize));
  }
}
