function testSummaryDuplicates(event) {
  let summaryInput = document.querySelector("#printer_issue_summary");
  let printer = document.querySelector("#printer_issue_printer").value;
  if (issueSummary[printer] == undefined) return;
  Object.keys(issueSummary[printer]).some((issue) => {
    if (summaryInput.value.toLowerCase().includes(issue.toLowerCase())) {
      document
        .getElementById("printer_issue_summary")
        .classList.add("is-invalid");
      return true;
    } else {
      document
        .getElementById("printer_issue_summary")
        .classList.remove("is-invalid");
    }
  });
}

if (typeof issueSummary != "undefined") {
  let summaryInput = document.querySelector("#printer_issue_summary");
  summaryInput.addEventListener("input", testSummaryDuplicates);
  document
    .querySelector("#printer_issue_printer")
    .addEventListener("input", testSummaryDuplicates);
}
