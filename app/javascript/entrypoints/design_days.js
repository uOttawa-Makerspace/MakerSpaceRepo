import Sortable from "sortablejs";

// Verify sheet ID
document.addEventListener("turbo:load", function () {
  let verifyDesignDaySheetButton = document.getElementById(
    "verifyDesignDaySheet",
  );

  let sheetKeyInput = document.getElementById("design_day_sheet_key");
  let sheetInvalidWarning = document.getElementById("sheet_key_may_be_invalid");
  let sheetKeyPreviewUrl = document.getElementById("sheet_key_preview_url");

  let sheetStatusVerified = document.getElementById("sheet_key_verified_icon");
  let sheetStatusMaybe = document.getElementById("sheet_key_maybe_icon");
  let sheetStatusError = document.getElementById("sheet_key_error_icon");

  function validationStatus(status) {
    sheetStatusVerified.hidden = !(status == "verified");
    sheetStatusMaybe.hidden = !(status == "maybe");
    sheetStatusError.hidden = !(status == "error");
  }

  function sheetNotFound() {
    //console.log("Sheet not found");
    sheetInvalidWarning.hidden = false;
    validationStatus("error");
  }

  function sheetFound(key) {
    //console.log("Sheet found");
    sheetKeyInput.value = key;
    sheetInvalidWarning.hidden = true;
    validationStatus("verified");
  }

  function verifySheetId() {
    // Crude test to make sure the sheet exists
    // Assuming user copy/pastes a sheet directly into input field
    let find_id = /[^/]{44}/; // Key is 44 characters long
    let url_or_key = sheetKeyInput.value;
    let key = find_id.exec(url_or_key.split("?")[0]); // remove any GET queries
    //console.log(`Potential key ${key}`);

    // Update url preview
    let urlStub = `https://docs.google.com/spreadsheets/d/${key || sheetKeyInput.value}`;
    sheetKeyPreviewUrl.href = urlStub;
    sheetKeyPreviewUrl.textContent = urlStub;

    if (key) {
      sheetFound(key);
    } else {
      sheetNotFound(key);
    }
  }

  if (verifyDesignDaySheetButton) {
    verifyDesignDaySheetButton.addEventListener("click", (event) => {
      event.preventDefault();
      verifySheetId();
    });
  }

  // Auto-verify on paste only
  if (sheetKeyInput) {
    sheetKeyInput.addEventListener("input", (event) => {
      validationStatus("maybe");
      // Field was changed
      if (event.inputType == "insertFromPaste") {
        verifySheetId();
      }
    });
  }
});

function addTemplateField(event) {
  // Prevent form submit
  event.preventDefault();

  // Get actual button with selector
  let btn = event.currentTarget;

  // Find template and clone
  let templateSelector = btn.dataset.templateFields;
  let template = document.querySelector(templateSelector);

  let newField = template.cloneNode(true);
  // Remove template attributes
  newField.removeAttribute("id");
  newField.removeAttribute("disabled");
  newField.hidden = false;

  // Find all elements named with template and replace with a random name, to
  // prevent conflicts
  let newName = Date.now();
  // XSS waiting to happen lol
  newField.innerHTML = newField.innerHTML.replaceAll("TEMPLATE", newName);
  // newField.querySelectorAll("[name], [for]").forEach((el) => {
  //   el.name = el.name.replaceAll("TEMPLATE", newName);
  // });

  // Insert above target button
  btn.insertAdjacentElement("beforebegin", newField);

  // Attach event listeners
  newField
    .querySelectorAll("[data-delete-template]")
    .forEach(attachRemoveTemplateField);

  // Redo ordering
  redoOrdering();
}

function attachRemoveTemplateField(target) {
  target.addEventListener("change", function (event) {
    if (event.currentTarget.checked) {
      event.currentTarget.closest("fieldset").hidden = true;
    }
  });
}

// Add/delete fields
document.addEventListener("turbo:load", function () {
  document.querySelectorAll("[data-template-fields]").forEach((el) => {
    el.addEventListener("click", addTemplateField);
  });

  document.querySelectorAll("[data-delete-template]").forEach((el) => {
    attachRemoveTemplateField(el);
  });
});

function redoOrdering() {
  // Set orderings first, as displayed client-side
  // querySelectorAll guarantees document order
  document
    .querySelectorAll("input.ordering-attribute")
    .forEach((el, index) => (el.value = index));
}

// Sorting schedules manually
document.addEventListener("turbo:load", function () {
  const studentList = document
    .querySelectorAll(".design-day-schedule-sort-list")
    .forEach((el) => {
      const studentSortable = new Sortable(el, {
        group: "design_day_schedule", // Same group for all
        handle: ".sort-handle",
        swapThreshold: 0.3,
        onSort: function (evt) {
          let toEventForValue = evt.to.dataset.eventFor;
          // Update event_for of dragged schedule
          let eventForInput = evt.item.querySelector(
            "input.event-for-attribute",
          );
          eventForInput.value = toEventForValue;

          // Update ordering of dragged schedule
          let orderingInput = evt.item.querySelector(
            "input.ordering-attribute",
          );
          // orderingInput.value = evt.newIndex;
          redoOrdering();

          console.log(
            `Moving to ${toEventForValue}: new event_for: ${eventForInput.value}, new order: ${orderingInput.value}`,
          );
        },
      });
    });
  redoOrdering();
});
