import TomSelect from "tom-select";
import DataTable from "datatables.net-bs5";
import "datatables.net-select-bs5";

function handleLinkInput(evt) {
  const url = this.value;
  // https://admin.shopify.com/store/uottawa-makerspace/products/10478024917048?link_source=search
  const match = url.match(/\/products\/(\d+)/i);
  const id = match ? match[1] : null;

  document.querySelector("#value").value = id;
}

document.addEventListener("turbo:load", function () {
  document.querySelectorAll("select.locker-variant-select").forEach((el) => {
    new TomSelect(el, {
      render: {
        option: function (data, escape) {
          let itemtitle = escape(data.text);
          let jsondata = JSON.parse(data.data);
          let title = escape(jsondata.displayName);
          let sku = escape(jsondata.sku);
          let price = escape(jsondata.price);
          return `<div>
                  <span>${itemtitle}</span> <br />
                  <span><b>Display Name:</b> ${title}</span> <br />
                  <span><b>SKU:</b> <code>${sku}</code></span> <br />
                  <span><b>Price:</b> <code>${price}</code></span>
                </div>`;
        },
      },
    });
  });

  let lockerProductLinkInput = document.querySelector("#shopifyProductLink");
  if (lockerProductLinkInput) {
    lockerProductLinkInput.addEventListener("input", handleLinkInput);
  }
});

document.addEventListener("turbo:load", function () {
  // Get all select dropdowns
  let lockerSizeSelects = document.querySelectorAll("[data-locker-size-for]");

  lockerSizeSelects.forEach((select) => {
    select.addEventListener("change", function () {
      // On select dropdown change, disable the dropdown while we send the
      // request. re-enable after we're done.
      this.tomselect.disable();

      // Find parent cell
      let cell = this.closest("td");

      // Show spinner
      let spinner = cell.querySelector(".spinner-border");
      spinner.hidden = false;

      let checkmark = cell.querySelector("i");

      let lockerId = this.dataset.lockerSizeFor;
      // console.log(`Changing ${lockerId} to ${this.value}`);

      const formData = new FormData();
      formData.append(this.name, this.value);

      fetch(`/lockers/${lockerId}`, {
        method: "PATCH",
        headers: {
          "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
        },
        body: formData,
      })
        .catch((error) => {
          console.error(error);
        })
        .finally(() => {
          // Hide spinner
          spinner.hidden = true;
          this.tomselect.enable();
          // Show checkmark
          checkmark.hidden = false;
          // Hide after 300ms
          setTimeout(() => {
            checkmark.hidden = true;
          }, 400);
        });
    });
  });

  // Toggle to prevent accidental changes
  let lockerEditToggle = document.querySelector("#lockerEditToggle");
  lockerEditToggle.addEventListener("change", function () {
    lockerSizeSelects.forEach((el) => {
      this.checked ? el.tomselect.enable() : el.tomselect.disable();
    });
  });
});

document.addEventListener("turbo:load", function () {
  // Setup table selection
  let locker_inventory_table = document.querySelector(
    "#locker_inventory_table",
  );
  locker_inventory_table &&
    new DataTable(locker_inventory_table, {
      columnDefs: [
        {
          orderable: false,
          render: DataTable.render.select(),
          targets: 0,
        },
      ],
      select: {
        style: "os",
        selector: "td:first-child",
      },
      order: [[1, "asc"]],
    });

  let lockerBulkEditList = document.querySelector("#lockerBulkEditList");

  // Clear list
  lockerBulkEditList.replaceChildren();

  // Fetch list of selected rows before modal submit
  let lockerBulkEditModal = document.querySelector("#lockerBulkEditModal");
  lockerBulkEditModal &&
    locker_inventory_table &&
    lockerBulkEditModal.addEventListener("show.bs.modal", (evt) => {
      // Get all selected lockers
      new DataTable(locker_inventory_table)
        .rows({ selected: true })
        .nodes()
        .each((el) => {
          console.log(el);
          const li = document.createElement("li");
          li.textContent = el.cells[1].innerText;
          lockerBulkEditList.appendChild(li);

          const field = document.createElement("input");
          field.type = "hidden";
          field.name = "id[]";
          field.value = el.dataset.lockerId;
          lockerBulkEditList.appendChild(field);
        });
    });
});
