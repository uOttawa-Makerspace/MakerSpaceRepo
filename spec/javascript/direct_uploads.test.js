// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const start = vi.hoisted(() => vi.fn());
vi.mock("@rails/actiontext", () => ({}));
vi.mock("@rails/activestorage", () => ({ start }));

await import("../../app/javascript/src/direct_uploads.js");
// read at load time, before any example runs
const startedOnLoad = start.mock.calls.length;

const PAGE = `
<form>
  <input type="file" id="pkg">
  <input type="submit" id="send" value="Save">
  <button type="submit" id="btn">Create <b>it</b></button>
</form>
<input id="video"><label id="video-label"></label>
<input id="video-2"><label id="video-label-2"></label>`;

const fire = (target, type, detail) => {
  const event = new CustomEvent(type, {
    detail,
    bubbles: true,
    cancelable: true,
  });
  target.dispatchEvent(event);
  return event;
};
const $ = (id) => document.getElementById(id);

beforeEach(() => {
  document.body.innerHTML = PAGE;
});

it("starts Active Storage", () => {
  expect(startedOnLoad).toBe(1);
});

describe("pasting into the editor", () => {
  const accept = (file) => {
    const event = new Event("trix-file-accept", { cancelable: true });
    event.file = file;
    document.dispatchEvent(event);
    return event;
  };

  beforeEach(() => vi.stubGlobal("alert", vi.fn()));

  it("allows an image", () => {
    const event = accept({ type: "image/png", size: 1000 });
    expect(event.defaultPrevented).toBe(false);
    expect(alert).not.toHaveBeenCalled();
  });

  it("refuses a file that is not an image", () => {
    const event = accept({ type: "application/pdf", size: 10 });
    expect(event.defaultPrevented).toBe(true);
    expect(alert).toHaveBeenCalledWith("Only images can be attached");
  });

  it("refuses an image over 5MB", () => {
    const event = accept({ type: "image/png", size: 5 * 1024 * 1024 + 1 });
    expect(event.defaultPrevented).toBe(true);
    expect(alert).toHaveBeenCalledWith("Image must be under 5MB");
  });

  it("logs the name of an attachment being uploaded", () => {
    const log = vi.spyOn(console, "log").mockImplementation(() => {});
    const add = (attachment) => {
      const event = new Event("trix-attachment-add");
      event.attachment = attachment;
      document.dispatchEvent(event);
    };
    add({ file: { name: "pic.png" } });
    expect(log).toHaveBeenCalledWith("Uploading:", "pic.png");
    log.mockClear();
    add({});
    expect(log).not.toHaveBeenCalled();
  });
});

describe("direct upload progress", () => {
  const init = () =>
    fire($("pkg"), "direct-upload:initialize", {
      id: 7,
      file: { name: "mod.zip" },
    });

  it("shows a progress bar and disables the submit buttons", () => {
    init();
    expect($("direct-upload-7")).not.toBeNull();
    expect($("direct-upload-7").textContent).toContain("mod.zip");
    expect($("pkg").nextElementSibling.id).toBe("direct-upload-7");
    expect($("send").disabled).toBe(true);
    expect($("btn").disabled).toBe(true);
    expect($("btn").innerHTML).toContain("Uploading package to storage");
    expect($("video").classList.contains("d-none")).toBe(true);
    expect($("video-label-2").classList.contains("d-none")).toBe(true);
  });

  it("works outside a form and without the video fields", () => {
    document.body.innerHTML = '<input type="file" id="pkg">';
    init();
    expect($("direct-upload-7")).not.toBeNull();
  });

  it("clears the pending state when the upload starts", () => {
    init();
    $("direct-upload-7").classList.add("direct-upload--pending");
    fire($("pkg"), "direct-upload:start", { id: 7 });
    expect(
      $("direct-upload-7").classList.contains("direct-upload--pending"),
    ).toBe(false);
    fire($("pkg"), "direct-upload:start", { id: 99 });
  });

  it("updates the bar and the rounded percentage", () => {
    init();
    fire($("pkg"), "direct-upload:progress", { id: 7, progress: 41.6 });
    expect($("direct-upload-progress-7").style.width).toBe("41.6%");
    expect($("direct-upload-percent-7").textContent).toBe("42%");
    fire($("pkg"), "direct-upload:progress", { id: 99, progress: 5 });
  });

  it("turns the bar green and says it is saving when the upload ends", () => {
    init();
    fire($("pkg"), "direct-upload:end", { id: 7 });
    expect($("direct-upload-progress-7").classList.contains("bg-success")).toBe(
      true,
    );
    expect(
      $("direct-upload-progress-7").classList.contains("progress-bar-animated"),
    ).toBe(false);
    expect($("direct-upload-percent-7").textContent).toBe(
      "Uploaded! Saving...",
    );
    expect($("btn").innerHTML).toContain("Saving module");
  });

  it("ends cleanly for an unknown upload and a page without a form", () => {
    document.body.innerHTML = '<input type="file" id="pkg">';
    fire($("pkg"), "direct-upload:end", { id: 1 });
  });

  it("reports a failure and restores the buttons", () => {
    init();
    const event = fire($("pkg"), "direct-upload:error", {
      id: 7,
      error: "Network down",
    });
    expect(event.defaultPrevented).toBe(true);
    expect($("direct-upload-7").classList.contains("border-danger")).toBe(true);
    expect($("direct-upload-7").textContent).toContain(
      "Direct upload failed: Network down",
    );
    expect($("send").disabled).toBe(false);
    expect($("btn").disabled).toBe(false);
    expect($("btn").innerHTML).toBe("Create <b>it</b>");
  });

  it("copes with a failure for an unknown upload outside a form", () => {
    document.body.innerHTML = '<input type="file" id="pkg">';
    fire($("pkg"), "direct-upload:error", { id: 5, error: "x" });
  });
});
