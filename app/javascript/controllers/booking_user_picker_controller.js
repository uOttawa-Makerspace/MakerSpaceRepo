import { Controller } from "@hotwired/stimulus";

import { newTomSelect } from "../src/tom_select.js";

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

// The admin panel's "Permit Access" user search on its select.
export default class extends Controller {
  connect() {
    userPicker(this.element);
  }
}
