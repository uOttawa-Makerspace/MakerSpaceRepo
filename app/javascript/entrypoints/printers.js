import { oncePerElement, onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

// The printer code shown beside the number follows the picked model.
const bindModelSelect = oncePerElement((modelSelect) => {
  modelSelect.addEventListener("change", (event) => {
    document.getElementById("newPrinterCode").innerText = event.target.options[
      event.target.selectedIndex
    ].text
      .match(/\((.*)\)/)
      .pop();
  });
  modelSelect.dispatchEvent(new Event("change"));
});

onEveryPageLoad(() => {
  const removePrinter = document.querySelector("#remove_printer");
  if (removePrinter) tomSelectFor(removePrinter, {});
  bindModelSelect(document.getElementById("model_id"));
});
