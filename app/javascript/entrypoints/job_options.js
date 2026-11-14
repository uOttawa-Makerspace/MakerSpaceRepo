import { tomSelectFor } from "../src/tom_select.js";
document.addEventListener("turbo:load", function () {
  const jobTypes = document.getElementById("job_type_ids_option");
  if (jobTypes) tomSelectFor(jobTypes, {});
});
