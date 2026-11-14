import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";
document.addEventListener("turbo:load", function () {
  if (document.getElementById("job_type_ids_option")) {
    if (!document.getElementById("job_type_ids_option").tomselect) {
      new TomSelect("#job_type_ids_option", tomSelectOptions(document, {}));
    }
  }
});
