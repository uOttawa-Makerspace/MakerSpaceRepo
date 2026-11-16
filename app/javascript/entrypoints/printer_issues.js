const summaryInput = document.querySelector("#printer_issue_summary");
const printerSelect = document.querySelector("#printer_issue_printer_id");

function testSummaryDuplicates() {
  const known = issueSummary[printerSelect.value];
  if (known === undefined) return;
  const text = summaryInput.value.toLowerCase();
  const duplicate = Object.keys(known).some((issue) =>
    text.includes(issue.toLowerCase()),
  );
  summaryInput.classList.toggle("is-invalid", duplicate);
}

if (typeof issueSummary != "undefined" && summaryInput && printerSelect) {
  summaryInput.addEventListener("input", testSummaryDuplicates);
  printerSelect.addEventListener("input", testSummaryDuplicates);
}
