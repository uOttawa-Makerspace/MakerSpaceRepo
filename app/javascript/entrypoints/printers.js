import TomSelect from "tom-select";
import { tomSelectOptions } from "../src/page_locale.js";

if (document.querySelector("#remove_printer")) {
  new TomSelect("#remove_printer", tomSelectOptions(document, {}));
}

if (document.getElementById("model_id")) {
  document.getElementById("model_id").addEventListener("change", (event) => {
    document.getElementById("newPrinterCode").innerText = event.target.options[
      event.target.selectedIndex
    ].text
      .match(/\((.*)\)/)
      .pop();
  });
  document.getElementById("model_id").dispatchEvent(new Event("change"));
}
