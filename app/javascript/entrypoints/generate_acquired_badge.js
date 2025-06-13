import Rails from "@rails/ujs";
document
  .getElementById("training_id_field")
  .addEventListener("change", function () {
    generate_badge_acquired();
  });
document
  .getElementById("training_level_field")
  .addEventListener("change", function () {
    generate_badge_acquired();
  });

generate_badge_acquired();

function generate_badge_acquired() {
  let training_id = document.getElementById("training_id_field").value;
  console.log(training_id);
  let level = document.getElementById("training_level_field").value;
  console.log(level);
  Rails.ajax({
    type: "GET",
    url: "/proficient_projects/generate_acquired_badge",
    data: new URLSearchParams({
      training_id: training_id,
      level: level,
    }).toString(),
    success: (args) =>
      (document.getElementById("badge-acquired-text").innerHTML =
        "<p>" + args + "</p>"),
  });
}
