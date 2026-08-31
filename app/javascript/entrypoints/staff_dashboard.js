import DataTable from "datatables.net-bs5";
import { Modal } from "bootstrap";
import { staffDashboardChannelConnection } from "../channels/staff_dashboard_channel";

let notifyModal = null;
let modalClicked = false;
let autoHideTimer = null;

function setupModal() {
  const modalEl = document.getElementById("signinModal");
  if (!modalEl) return null;

  notifyModal = Modal.getOrCreateInstance(modalEl);
  const progressBar = document.getElementById("outer-progress-bar");

  modalEl.addEventListener("click", () => {
    modalClicked = true;
    if (progressBar) progressBar.classList.add("fading-progress-bar");
  });

  modalEl.addEventListener("hidden.bs.modal", () => {
    if (progressBar) progressBar.classList.remove("fading-progress-bar");
  });

  return notifyModal;
}

function hideModal() {
  if (!modalClicked && notifyModal) {
    notifyModal.hide();
  }
}

function isNotificationDisabled() {
  const popupEnabledCheck = document.querySelector("input#popup_enabled");
  if (popupEnabledCheck && !popupEnabledCheck.checked) return true;

  const userSearchBar = document.querySelector("#user_dashboard_select");
  if (
    userSearchBar?.tomselect?.isOpen &&
    userSearchBar.tomselect.inputValue() !== ""
  ) {
    return true;
  }

  return false;
}

async function refreshCapacity() {
  const el = document.querySelector(".max_capacity_alert");
  if (!el) return;

  const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content;
  try {
    const response = await fetch("/staff_dashboard/refresh_capacity", {
      headers: {
        "X-Requested-With": "XMLHttpRequest",
        Accept: "text/html",
        "X-CSRF-Token": csrfToken || "",
      },
    });
    if (response.ok) {
      el.innerHTML = await response.text();
    }
  } catch (error) {
    console.error("Failed to refresh capacity:", error);
  }
}

function userTapIn(user) {
  if (isNotificationDisabled()) return;

  const modalInstance = setupModal();
  if (!modalInstance) return;

  const innerBar = document.getElementById("signin-progress-bar");
  if (innerBar) innerBar.classList.add("moving-progress-bar");

  const setElText = (id, text) => {
    const el = document.getElementById(id);
    if (el) el.innerText = text;
  };

  const toggleEl = (id, show) => {
    const el = document.getElementById(id);
    if (el) el.style.display = show ? "block" : "none";
  };

  setElText("sign-in-username", user.username || "");
  const profileLink = document.getElementById("sign-in-profile-link");
  if (profileLink) profileLink.href = user.username || "#";

  setElText("sign-in-email", user.email || "");
  toggleEl("no-membership", !user.membership);
  toggleEl("has-membership", user.membership);
  setElText("sign-in-membership", `Active until ${user.expiration_date || ""}`);

  toggleEl("not-student", !user.is_student);
  toggleEl("is-student", user.is_student);
  toggleEl("unsigned-consent-form", !user.signed_sheet);
  toggleEl("signed-consent-form", user.signed_sheet);

  const certContainer = document.getElementById("sign-in-certifications");
  if (certContainer && Array.isArray(user.certification)) {
    const certBadges = user.certification
      .map(
        (name) =>
          `<span class="badge text-bg-light text-black-50">${name}</span>`,
      )
      .join(" ");
    certContainer.innerHTML = `<span class="fs-4">${certBadges}</span>`;
  }

  const tableEl = document.querySelector("#signed-in-table");
  if (tableEl && DataTable.isDataTable(tableEl)) {
    new DataTable(tableEl).draw();
  }

  modalClicked = false;
  modalInstance.show();
  clearTimeout(autoHideTimer);
  autoHideTimer = setTimeout(hideModal, 6000);
}

document.addEventListener("turbo:load", () => {
  setupModal();
  refreshCapacity();

  const signinForm = document.getElementById("sign_in_user_fastsearch");
  if (signinForm) {
    signinForm.onsubmit = () => {
      const selectVal = document.getElementById("user_dashboard_select")?.value;
      const targetInput = document.getElementById(
        "sign_in_user_fastsearch_username",
      );
      if (targetInput && selectVal) targetInput.value = selectVal;
    };
  }

  const searchForm = document.getElementById("search_user_fastsearch");
  if (searchForm) {
    searchForm.onsubmit = () => {
      const selectVal = document.getElementById("user_dashboard_select")?.value;
      const targetInput = document.getElementById(
        "search_user_fastsearch_username",
      );
      if (targetInput && selectVal) targetInput.value = selectVal;
    };
  }

  const excelInput = document.querySelector(".form-control-input-excel");
  if (excelInput) {
    excelInput.addEventListener("change", (e) => {
      const input = document.getElementById("excel-input");
      if (input?.files?.[0] && e.target.nextElementSibling) {
        e.target.nextElementSibling.innerText = input.files[0].name;
      }
    });
  }

  staffDashboardChannelConnection((data) => {
    if (data?.add_user) {
      userTapIn(data.add_user);
    }
  });
});

document.addEventListener("turbo:before-stream-render", (event) => {
  const originalRender = event.detail.render;
  const tables = document.querySelectorAll("table.dataTable");

  event.detail.render = function (streamElement) {
    tables.forEach((t) => {
      if (DataTable.isDataTable(t)) {
        new DataTable(t).destroy();
      }
    });

    originalRender(streamElement);

    tables.forEach((t) => {
      new DataTable(t);
    });
  };
});
