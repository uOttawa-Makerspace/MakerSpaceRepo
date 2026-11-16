import TomSelect from "tom-select";
import { tomSelectOptions } from "./page_locale.js";

// TomSelect sets the select's tabindex to -1 and uses the select's own tabindex
// for its control. The tabindex the view gave the select (often none) is kept
// on the select, so a cached copy can give it back.
function rememberTabIndex(el) {
  el.dataset.viewTabindex = el.getAttribute("tabindex") ?? "";
}

function restoreTabIndex(el) {
  const viewTabindex = el.dataset.viewTabindex;
  if (viewTabindex) el.setAttribute("tabindex", viewTabindex);
  else el.removeAttribute("tabindex");
}

// A page Turbo restores from its cache is a copy of the page as it was left: a
// select on it still carries the markup of its TomSelect, but no TomSelect.
// That markup is removed first, so the new TomSelect replaces it rather than
// adding a second one beside it, and can be reached with Tab like the first.
function clearCachedTomSelect(el) {
  if (!el.classList.contains("tomselected")) return;
  const wrapper = el.nextElementSibling;
  if (wrapper && wrapper.classList.contains("ts-wrapper")) wrapper.remove();
  el.classList.remove("tomselected", "ts-hidden-accessible");
  restoreTabIndex(el);
}

// A TomSelect for the select, with its texts in the page's language, in place
// of any copy of an earlier one a cache restore left beside it.
export function newTomSelect(el, options) {
  clearCachedTomSelect(el);
  rememberTabIndex(el);
  return new TomSelect(el, tomSelectOptions(el, options));
}

// The select's TomSelect: the one an earlier load of the same page gave it, or
// a new one. Turbo runs a page's scripts again on every visit and restore.
export function tomSelectFor(el, options) {
  return el.tomselect ?? newTomSelect(el, options);
}
