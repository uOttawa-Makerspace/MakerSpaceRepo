import "@rails/actiontext";
import * as ActiveStorage from "@rails/activestorage";
ActiveStorage.start();

// For when images get pasted into the trix editor
document.addEventListener("trix-file-accept", (e) => {
  if (!e.file.type.startsWith("image/")) {
    e.preventDefault();
    alert("Only images can be attached");
    return;
  }
  if (e.file.size > 5 * 1024 * 1024) {
    e.preventDefault();
    alert("Image must be under 5MB");
  }
});

document.addEventListener("trix-attachment-add", (e) => {
  const { attachment } = e;
  if (attachment.file) {
    console.log("Uploading:", attachment.file.name);
  }
});

// Direct Upload Event Handlers with Bootstrap Progress Bars
addEventListener("direct-upload:initialize", (event) => {
  const { target, detail } = event;
  const { id, file } = detail;

  // Optional video elements cleanup if they exist
  const video = document.getElementById("video");
  const videoLabel = document.getElementById("video-label");
  const video2 = document.getElementById("video-2");
  const videoLabel2 = document.getElementById("video-label-2");
  if (video) video.classList.add("d-none");
  if (videoLabel) videoLabel.classList.add("d-none");
  if (video2) video2.classList.add("d-none");
  if (videoLabel2) videoLabel2.classList.add("d-none");

  // Disable form submit buttons while uploading
  const form = target.closest("form");
  if (form) {
    form
      .querySelectorAll("input[type=submit], button[type=submit]")
      .forEach((btn) => {
        btn.disabled = true;
        btn.dataset.originalText = btn.innerHTML || btn.value;
        btn.innerHTML =
          '<i class="fa fa-spinner fa-spin me-1"></i> Uploading package to storage...';
      });
  }

  // Insert Bootstrap progress bar directly below the input
  target.insertAdjacentHTML(
    "afterend",
    `
    <div id="direct-upload-${id}" class="direct-upload my-2 p-2 border rounded bg-body-tertiary">
      <div class="d-flex justify-content-between small mb-1">
        <span class="direct-upload__filename fw-bold text-truncate" style="max-width: 80%;">${file.name}</span>
        <span id="direct-upload-percent-${id}" class="text-muted">0%</span>
      </div>
      <div class="progress" style="height: 10px;">
        <div id="direct-upload-progress-${id}" class="progress-bar progress-bar-striped progress-bar-animated bg-primary" role="progressbar" style="width: 0%"></div>
      </div>
    </div>
  `,
  );
});

addEventListener("direct-upload:start", (event) => {
  const { id } = event.detail;
  const element = document.getElementById(`direct-upload-${id}`);
  if (element) element.classList.remove("direct-upload--pending");
});

addEventListener("direct-upload:progress", (event) => {
  const { id, progress } = event.detail;
  const progressElement = document.getElementById(
    `direct-upload-progress-${id}`,
  );
  const percentElement = document.getElementById(`direct-upload-percent-${id}`);
  if (progressElement) progressElement.style.width = `${progress}%`;
  if (percentElement) percentElement.textContent = `${Math.round(progress)}%`;
});

addEventListener("direct-upload:error", (event) => {
  event.preventDefault();
  const { id, error } = event.detail;
  const element = document.getElementById(`direct-upload-${id}`);
  if (element) {
    element.classList.add("border-danger");
    element.innerHTML = `<div class="text-danger small"><i class="fa fa-exclamation-triangle"></i> Direct upload failed: ${error}</div>`;
  }
  const form = event.target.closest("form");
  if (form) {
    form
      .querySelectorAll("input[type=submit], button[type=submit]")
      .forEach((btn) => {
        btn.disabled = false;
        if (btn.dataset.originalText) btn.innerHTML = btn.dataset.originalText;
      });
  }
});

addEventListener("direct-upload:end", (event) => {
  const { id } = event.detail;
  const progressElement = document.getElementById(
    `direct-upload-progress-${id}`,
  );
  const percentElement = document.getElementById(`direct-upload-percent-${id}`);
  if (progressElement) {
    progressElement.classList.remove("progress-bar-animated");
    progressElement.classList.add("bg-success");
  }
  if (percentElement) percentElement.textContent = "Uploaded! Saving...";

  const form = event.target.closest("form");
  if (form) {
    form
      .querySelectorAll("input[type=submit], button[type=submit]")
      .forEach((btn) => {
        btn.innerHTML =
          '<i class="fa fa-spinner fa-spin me-1"></i> Saving module...';
      });
  }
});
