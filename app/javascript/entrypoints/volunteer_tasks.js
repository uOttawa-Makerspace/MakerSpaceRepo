// app/javascript/entrypoints/volunteer_tasks.js
import TomSelect from "tom-select";

function initTomSelect(selector, options) {
  const el = document.querySelector(selector);
  if (el && !el.tomselect) {
    new TomSelect(el, options);
  }
}

document.addEventListener("turbo:load", function () {
  // ------------------------------------------------------------------------
  // 1. Task Form TomSelects
  // ------------------------------------------------------------------------
  initTomSelect("#user_id", {
    placeholder: "Select a user",
    maxItems: 1,
    plugins: ["remove_button"],
  });

  initTomSelect("#task_certifications", {
    plugins: ["remove_button"],
    maxItems: null,
    sortField: [{ field: "text" }],
  });

  initTomSelect("#volunteer_id", {
    plugins: ["remove_button"],
    maxItems: null,
    sortField: [{ field: "text" }],
  });

  initTomSelect("#staff_id", {
    maxItems: 1,
    sortField: [{ field: "text" }],
  });

  initTomSelect("#remove_staff_id", {
    plugins: ["remove_button"],
    maxItems: null,
    closeAfterSelect: true,
  });

  initTomSelect("#remove_volunteer_id", {
    plugins: ["remove_button"],
    maxItems: null,
    closeAfterSelect: true,
  });

  // ------------------------------------------------------------------------
  // 2. Task Form Image Removals & Completed Task Toggler
  // ------------------------------------------------------------------------
  document.querySelectorAll(".image-remove").forEach((el) => {
    el.addEventListener("click", (e) => {
      e.preventDefault();
      e.stopPropagation();
      const deleteImagesInput = document.getElementById("deleteimages");
      if (deleteImagesInput) {
        deleteImagesInput.value += el.id + ",";
      }
      el.parentElement.remove();
    });
  });

  const hider = document.getElementById("task-hider");
  if (hider) {
    const completedRows = document.querySelectorAll(
      'tr[completed="completed"]',
    );
    hider.addEventListener("click", () => {
      completedRows.forEach((row) => row.classList.toggle("d-none"));
      hider.innerHTML =
        hider.innerHTML === "Hide Completed Task"
          ? "Show Completed Task"
          : "Hide Completed Task";
    });
  }

  // ------------------------------------------------------------------------
  // 3. Volunteer Tasks Index Filter & Search Engine
  // ------------------------------------------------------------------------
  const taskIndexContainer = document.getElementById("volunteerTasksIndex");
  if (taskIndexContainer) {
    const spaceEl = document.getElementById("spaceFilter");
    const categoryEl = document.getElementById("categoryFilter");
    const certEl = document.getElementById("certFilter");
    const searchInput = document.getElementById("taskSearchInput");

    let spaceTom = null;
    let categoryTom = null;
    let certTom = null;

    if (spaceEl && !spaceEl.tomselect) {
      spaceTom = new TomSelect(spaceEl, {
        allowEmptyOption: true,
        create: false,
        controlInput: null,
      });
    } else if (spaceEl) {
      spaceTom = spaceEl.tomselect;
    }

    if (categoryEl && !categoryEl.tomselect) {
      categoryTom = new TomSelect(categoryEl, {
        allowEmptyOption: true,
        create: false,
        controlInput: null,
      });
    } else if (categoryEl) {
      categoryTom = categoryEl.tomselect;
    }

    if (certEl && !certEl.tomselect) {
      certTom = new TomSelect(certEl, {
        plugins: ["remove_button"],
        create: false,
        placeholder: "Filter by Certifications...",
      });
    } else if (certEl) {
      certTom = certEl.tomselect;
    }

    function applyTaskCardFilters() {
      const query = searchInput ? searchInput.value.toLowerCase().trim() : "";
      const selectedSpace = spaceTom ? spaceTom.getValue().toLowerCase() : "";
      const selectedCategory = categoryTom
        ? categoryTom.getValue().toLowerCase()
        : "";
      const selectedCerts = certTom ? certTom.getValue() : [];

      const cards = taskIndexContainer.querySelectorAll(".task-item-card-col");

      cards.forEach((card) => {
        const cardText = (
          card.getAttribute("data-searchable-text") || ""
        ).toLowerCase();
        const cardSpace = (card.getAttribute("data-space") || "").toLowerCase();
        const cardCategory = (
          card.getAttribute("data-category") || ""
        ).toLowerCase();
        const cardCerts = (
          card.getAttribute("data-certifications") || ""
        ).toLowerCase();

        const matchesQuery = !query || cardText.includes(query);
        const matchesSpace = !selectedSpace || cardSpace === selectedSpace;
        const matchesCategory =
          !selectedCategory || cardCategory === selectedCategory;
        const matchesCerts =
          selectedCerts.length === 0 ||
          selectedCerts.some((cert) => cardCerts.includes(cert.toLowerCase()));

        if (matchesQuery && matchesSpace && matchesCategory && matchesCerts) {
          card.style.display = "";
        } else {
          card.style.display = "none";
        }
      });
    }

    if (searchInput)
      searchInput.addEventListener("input", applyTaskCardFilters);
    if (spaceTom) spaceTom.on("change", applyTaskCardFilters);
    if (categoryTom) categoryTom.on("change", applyTaskCardFilters);
    if (certTom) certTom.on("change", applyTaskCardFilters);
  }
});
