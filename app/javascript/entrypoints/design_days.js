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
    let find_id = /[^/]{44}/;
    let url_or_key = sheetKeyInput.value;
    let key = find_id.exec(url_or_key.split("?"));
    console.log(`Potential key ${key}`);

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
