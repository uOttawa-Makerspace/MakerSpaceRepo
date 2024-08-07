import TomSelect from "tom-select";
new TomSelect("#remove_printer", {});

document.getElementById("model_id").addEventListener("change", (event) => {
  document.getElementById("newPrinterCode").innerText = event.target.options[
    event.target.selectedIndex
  ].text
    .match(/\((.*)\)/)
    .pop();
});
document.getElementById("model_id").dispatchEvent(new Event("change"));
