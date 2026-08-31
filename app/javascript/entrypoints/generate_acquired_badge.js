document
  .getElementById("training_id_field")
  ?.addEventListener("change", generate_badge_acquired);

document
  .getElementById("training_level_field")
  ?.addEventListener("change", generate_badge_acquired);

generate_badge_acquired();

async function generate_badge_acquired() {
  const trainingIdInput = document.getElementById("training_id_field");
  const levelInput = document.getElementById("training_level_field");
  const badgeContainer = document.getElementById("badge-acquired-text");

  if (!trainingIdInput || !levelInput || !badgeContainer) return;

  const params = new URLSearchParams({
    training_id: trainingIdInput.value,
    level: levelInput.value,
  });

  try {
    const response = await fetch(
      `/proficient_projects/generate_acquired_badge?${params.toString()}`,
      {
        headers: { Accept: "text/plain, text/html" },
      },
    );

    if (response.ok) {
      const text = await response.text();
      badgeContainer.innerHTML = `<p>${text}</p>`;
    }
  } catch (error) {
    console.error("Error generating badge:", error);
  }
}
