import { onEveryPageLoad } from "../src/on_page.js";
import { tomSelectFor } from "../src/tom_select.js";

onEveryPageLoad(() => {
  const jobTypes = document.getElementById("job_type_ids_option");
  if (jobTypes) tomSelectFor(jobTypes, {});
});
