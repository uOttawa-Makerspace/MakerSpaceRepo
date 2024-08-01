import TomSelect from "tom-select";
const all_selects = ["#ultimaker2p", "#ultimaker3", "#replicator2", "#dremel"];
for (let i = 0; i < all_selects.length; i++) {
  try {
    new TomSelect(all_selects[i], {});
  } catch (e) {} // nothing to catch O_O
}

try {
  new TomSelect("#printerNumberSelect", { items: [] }); // To claer default value
} catch (e) {}
