import { newTomSelect } from "../src/tom_select.js";
document.addEventListener("turbo:load", function () {
  if (document.getElementById("user_id")) {
    if (!document.getElementById("user_id").tomselect) {
      const instructor = /** @type {HTMLSelectElement} */ (
        document.getElementById("user_id")
      );
      newTomSelect(instructor, {
        maxItems: 1,
        plugins: ["remove_button"],
      });
    }
  }
});
