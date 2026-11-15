import "flatpickr";
import { DATE_TIME, flatpickrOptions } from "../src/page_locale.js";
import { newTomSelect } from "../src/tom_select.js";

// The calendar, its modal and toast, the recurring approval and the select-all
// boxes are Stimulus controllers; what stays here has no controller of its own.

// The admin user picker. The server does the matching (name or username, at least `minLength`
// characters), and the list always obeys one rule: it holds only the server's answer for exactly the text
// now in the box, and nothing when that text is shorter than the minimum.
//  - an answer is accepted only if its query is still the text in the box, and the response is OK;
//  - whenever the text differs from the answered query (typing, or Tom Select itself emptying the box on
//    selection, close or clear) the options are dropped before anything is shown.
// `score` always 1 keeps Tom Select from filtering the server's matches again by name.
function userPicker(select) {
  if (select.tomselect) return; // made by an earlier load of the same page
  const minLength = Number(select.dataset.minLength);
  const hint = select.dataset.hint;
  let answeredQuery = null;

  const picker = newTomSelect(select, {
    plugins: ["remove_button"],
    valueField: "id",
    labelField: "name",
    searchField: ["name"],
    options: [],
    score: () => () => 1,
    shouldLoad: (query) => query.length >= minLength,
    render: {
      not_loading: () => {
        const el = document.createElement("div");
        el.className = "no-results";
        el.textContent = hint;
        return el;
      },
    },
    /** @this {import("tom-select").default} */
    load(query, callback) {
      // an unanswered lookup is forgotten, so typing the same text again asks the server again
      const skip = () => {
        delete this.loadedSearches[query];
        callback();
      };
      const answer = (people) => {
        if (!people || this.inputValue() !== query) return skip();
        answeredQuery = query;
        callback(people);
      };
      if (this.inputValue() !== query) return skip();
      fetch(`/sub_space_booking/users?query=${encodeURIComponent(query)}`)
        .then((r) => (r.ok ? r.json() : null))
        .then(answer, skip);
    },
  });

  const dropStaleOptions = () => {
    if (answeredQuery === null || answeredQuery === picker.inputValue()) return;
    answeredQuery = null;
    picker.clearOptions();
    picker.refreshOptions(false);
  };
  picker.hook("before", "refreshOptions", dropStaleOptions);
  picker.hook("after", "onInput", dropStaleOptions);
  picker.hook("after", "setTextboxValue", dropStaleOptions);
  return picker;
}

// The access-request form, the admin "grant access" user search and the edit
// page's pickers, set up again on every visit.
document.addEventListener("turbo:load", function () {
  const supervisorsContainer = document.getElementById("supervisor-select");
  document.querySelectorAll(".identity-button").forEach((btn) => {
    btn.addEventListener("click", (e) => {
      if (supervisorsContainer)
        supervisorsContainer.style.display =
          e.target.value === "Staff" ? "block" : "none";
    });
  });

  const userSelect = document.getElementById("user_booking_select");
  if (userSelect) userPicker(userSelect);

  ["sub_space_booking_start_time", "sub_space_booking_end_time"].forEach((id) =>
    document
      .getElementById(id)
      ?.flatpickr(flatpickrOptions(document, DATE_TIME, "date_time")),
  );
});

// ─── Tab routing (turbo:render + initial load) ────────────────────────────────

function makeActive(tab, param) {
  let tabContent = document.getElementById(tab);
  let tabButton = document.getElementById(tab + "-btn");
  let tabButtons = document.getElementsByClassName("nav-link");
  if (!(tabContent && tabButton && tabButtons)) {
    return;
  }
  [...tabButtons].forEach((button) => {
    button.classList.remove("active");
  });
  tabButton.classList.add("active");
  let tabContents = document.getElementsByClassName("tab-pane");
  [...tabContents].forEach((content) => {
    content.classList.remove("active");
    content.classList.remove("show");
  });
  tabContent.classList.add("active");
  tabContent.classList.add("show");

  if (param && tab === "booking-admin-tab") {
    let table = document.getElementById(param);
    // SAFETY CHECK: Prevents JS from crashing if the ID isn't found
    if (table) {
      table.scrollIntoView({
        behavior: "smooth",
        block: "start",
        inline: "nearest",
      });
      window.scrollBy(
        0,
        -7 * parseFloat(getComputedStyle(document.documentElement).fontSize),
      );
    }
  }
}

function ready() {
  const anchor = window.location.hash.replace("#", "");
  const params = new URLSearchParams(window.location.search);

  const paramToSection = {
    pending_page: "pendingBody",
    approved_page: "approvedBody",
    denied_page: "declinedBody",
    old_pending_page: "pastPendingBody",
    old_approved_page: "pastApprovedBody",
    old_denied_page: "pastDeclinedBody",
  };

  let scrollTarget = null;
  for (const [key, sectionId] of Object.entries(paramToSection)) {
    if (params.has(key)) {
      scrollTarget = sectionId;
      break;
    }
  }

  if (anchor) {
    makeActive(anchor, null);
  } else if (scrollTarget) {
    makeActive("booking-admin-tab", scrollTarget);
  } else {
    makeActive("booking-calendar-tab", null);
  }
}

// Wire up tab buttons (outside turbo:load so they survive re-renders)
document.querySelectorAll(".tab-link").forEach((btn) => {
  btn.addEventListener("click", (e) => {
    e.preventDefault();
    e.stopPropagation();
    // id is e.g. "booking-calendar-tab-btn" → target is "booking-calendar-tab"
    const target =
      btn.getAttribute("data-bs-target")?.replace("#", "") ??
      btn.id.replace("-btn", "");
    makeActive(target, null);
  });
});

document.addEventListener("turbo:render", ready);
ready();
