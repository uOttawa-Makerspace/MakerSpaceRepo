import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";
document.addEventListener("turbo:load", function () {
  if (document.getElementById("user_id")) {
    if (!document.getElementById("user_id").tomselect) {
      const instructor = /** @type {HTMLSelectElement} */ (
        document.getElementById("user_id")
      );
      new TomSelect(
        instructor,
        tomSelectOptions(instructor, {
          maxItems: 1,
          plugins: ["remove_button"],
        }),
      );
    }
  }
});
