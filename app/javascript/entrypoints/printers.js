import TomSelect from "tom-select";

if (document.querySelector("#remove_printer")) {
  new TomSelect("#remove_printer", {});
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
