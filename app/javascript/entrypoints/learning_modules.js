import Sortable from "sortablejs";
import TomSelect from "tom-select";
import { csrfHeaders } from "../src/csrf";
import { reportFailure, requestJson } from "../src/request_error";

document.addEventListener("turbo:load", () => {
  document.querySelectorAll("[data-order]").forEach((reorderSwitch) => {
    // Find order container
    const modules = document.querySelector(
      `[data-order-container='${reorderSwitch.dataset.order}']`,
    );
    // Attach sortable
    let sortable = new Sortable(modules, {
      sort: reorderSwitch.checked,
      handle: ".sort-handle",
      onEnd: (e) => {
        requestJson("/learning_area/reorder", {
          method: "PUT",
          headers: csrfHeaders({
            Accept: "application/json",
            "Content-Type": "application/json",
          }),
          body: JSON.stringify({
            data: [...e.from.children].map((c) => c.dataset.id),
            format: "json",
          }),
        }).catch(reportFailure);
      },
    });

    reorderSwitch.addEventListener("change", (ev) => {
      sortable.option("sort", ev.currentTarget.checked);
      modules
        .querySelectorAll(".sort-handle")
        .forEach((el) => (el.hidden = !ev.currentTarget.checked));
    });
  });

  let subskill = document.querySelector("#learning_module_subskill");
  if (subskill) {
    new TomSelect(subskill, {
      maxItems: 1,
      plugins: ["remove_button"],
      create: true,
    });
  }
});
