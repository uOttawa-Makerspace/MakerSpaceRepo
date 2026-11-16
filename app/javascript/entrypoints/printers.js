import { oncePerElement, onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

// The short form in brackets of the picked model's name; none when no model is
// picked or its name has no short form.
function pickedModelCode(modelSelect) {
  const name = modelSelect.options[modelSelect.selectedIndex]?.text ?? "";
  return name.match(/\((.*)\)/)?.[1] ?? "";
}

// The printer code shown beside the number follows the picked model.
const bindModelSelect = oncePerElement((modelSelect) => {
  modelSelect.addEventListener("change", () => {
    document.getElementById("newPrinterCode").innerText =
      pickedModelCode(modelSelect);
  });
  modelSelect.dispatchEvent(new Event("change"));
});

onEveryPageLoad(() => {
  const removePrinter = document.querySelector("#remove_printer");
  if (removePrinter) tomSelectFor(removePrinter, {});
  bindModelSelect(document.getElementById("model_id"));
});
