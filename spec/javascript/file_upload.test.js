// @vitest-environment happy-dom
import { beforeEach, describe, expect, it, vi } from "vitest";

const sortables = [];
vi.mock("sortablejs", () => ({
  default: { create: (el, options) => sortables.push({ el, options }) },
}));

// The test environment has no blob URLs or a settable files list.
const revoked = [];
globalThis.URL.createObjectURL = (file) => `blob:${file.name}`;
globalThis.URL.revokeObjectURL = (url) => revoked.push(url);
globalThis.DataTransfer = class {
  constructor() {
    this.files = [];
    this.items = { add: (file) => this.files.push(file) };
  }
};
Object.defineProperty(HTMLInputElement.prototype, "files", {
  configurable: true,
  get() {
    return this._files ?? [];
  },
  set(value) {
    this._files = value;
  },
});

const file = (name, type = "image/png") => new File(["x"], name, { type });

function setup(
  html,
  { inputAttrs = 'data-file-upload-prefix="repo[photos]"' } = {},
) {
  document.body.innerHTML = `
    <div class="file-upload-drop-zone" id="zone">
      <input type="file" id="in" data-file-upload-helper name="project[files][]"
             data-file-upload-preview-selector="#preview" ${inputAttrs}>
    </div>
    <div id="preview" ${html.attrs ?? ""}>${html.items ?? ""}</div>`;
  document.dispatchEvent(new Event("turbo:load"));
  return {
    input: document.getElementById("in"),
    preview: document.getElementById("preview"),
    zone: document.getElementById("zone"),
  };
}

const choose = (input, files) => {
  input.files = files;
  input.dispatchEvent(new Event("change"));
};
const items = (preview) => [
  ...preview.querySelectorAll(".file-upload-item-preview"),
];

await import("../../app/javascript/src/file_upload.js");

beforeEach(() => {
  sortables.length = 0;
  revoked.length = 0;
  vi.spyOn(console, "warn").mockImplementation(() => {});
});

describe("choosing files", () => {
  it("previews each file with its name and a hidden file field", () => {
    const { input, preview } = setup({});
    choose(input, [file("a.png"), file("b.png")]);

    const rows = items(preview);
    expect(rows).toHaveLength(2);
    expect(rows[0].querySelector("span").textContent).toBe("a.png");
    expect(rows[0].querySelector("img").src).toBe("blob:a.png");
    // The file name beside the thumbnail names it, so the image is decorative.
    expect(rows[0].querySelector("img").getAttribute("alt")).toBe("");
    const field = rows[0].querySelector("input[type=file]");
    expect(field.hidden).toBe(true);
    expect(field.name).toBe("repo[photos][]");
    expect(field.files).toHaveLength(1);
  });

  it("takes the field prefix from the name and stops carrying the name itself", () => {
    const { input, preview } = setup({}, { inputAttrs: "" });
    expect(input.hasAttribute("name")).toBe(false);
    choose(input, [file("a.png")]);
    expect(items(preview)[0].querySelector("input[type=file]").name).toBe(
      "project[files][]",
    );
  });

  it("names the field with an index and suffix for nested attributes", () => {
    const { input, preview } = setup(
      {},
      {
        inputAttrs:
          'data-file-upload-prefix="repo[photos_attributes]" data-file-upload-suffix="image"',
      },
    );
    choose(input, [file("a.png")]);
    expect(items(preview)[0].querySelector("input[type=file]").name).toMatch(
      /^repo\[photos_attributes\]\[\d+\]\[image\]$/,
    );
  });

  it.each([
    ["photos_attributes", "image"],
    ["repo_files_attributes", "file"],
  ])("assumes the %s suffix is %s", (prefix, suffix) => {
    const { input, preview } = setup(
      {},
      { inputAttrs: `data-file-upload-prefix="repo[${prefix}]"` },
    );
    choose(input, [file("a.png")]);
    expect(items(preview)[0].querySelector("input[type=file]").name).toMatch(
      new RegExp(`\\[${suffix}\\]$`),
    );
  });

  it("stops adding files at the limit, counting those already there", () => {
    const { input, preview } = setup(
      {},
      {
        inputAttrs:
          'data-file-upload-prefix="repo[photos]" data-file-upload-limit="2"',
      },
    );
    choose(input, [file("a.png"), file("b.png"), file("c.png")]);
    expect(
      items(preview).map((r) => r.querySelector("span").textContent),
    ).toEqual(["a.png", "b.png"]);
    choose(input, [file("d.png")]);
    expect(items(preview)).toHaveLength(2);
  });

  it("removes a new file when its Delete button is clicked", () => {
    const { input, preview } = setup({});
    choose(input, [file("a.png"), file("b.png")]);
    items(preview)[0].querySelector(".file-upload-item-delete").click();
    expect(items(preview)).toHaveLength(1);
  });

  it("replaces a thumbnail that cannot load and frees its blob URL", () => {
    const { input, preview } = setup({});
    choose(input, [file("a.png")]);
    const img = preview.querySelector("img");
    img.dispatchEvent(new Event("error"));
    expect(revoked).toEqual(["blob:a.png"]);
    expect(preview.querySelector(".file-upload-preview-failed")).not.toBeNull();
    expect(preview.querySelector("img")).toBeNull();
  });

  it("frees the blob URL once the thumbnail has loaded", () => {
    const { input, preview } = setup({});
    choose(input, [file("a.png")]);
    preview.querySelector("img").dispatchEvent(new Event("load"));
    expect(revoked).toEqual(["blob:a.png"]);
  });
});

describe("existing items", () => {
  const existing = (n) => `
    <div class="file-upload-item-preview" id="old${n}">
      <input type="hidden" data-file-upload-position value="9">
      <input type="hidden" data-file-upload-hidden-destroy value="false">
      <button type="button" data-file-upload-item-delete></button>
    </div>`;

  it("hides a server rendered item and marks it for removal", () => {
    const { preview } = setup({ items: existing(1) });
    preview.querySelector("[data-file-upload-item-delete]").click();
    expect(preview.querySelector("#old1").hidden).toBe(true);
    expect(
      preview.querySelector("[data-file-upload-hidden-destroy]").value,
    ).toBe("true");
  });

  it("ignores an item without a delete control", () => {
    const { preview } = setup({
      items: '<div class="file-upload-item-preview"></div>',
    });
    expect(items(preview)).toHaveLength(1);
  });
});

describe("sortable gallery", () => {
  const attrs = { attrs: "data-file-upload-sortable" };

  it("numbers items in order and adds drag handles to existing ones", () => {
    const { input, preview } = setup(
      {
        ...attrs,
        items: `<div class="file-upload-item-preview" id="old1">
                <input type="hidden" data-file-upload-position value="5"></div>`,
      },
      {
        inputAttrs:
          'data-file-upload-prefix="repo[photos_attributes]" data-file-upload-suffix="image"',
      },
    );

    expect(
      preview.querySelector("#old1 .file-upload-drag-handle"),
    ).not.toBeNull();
    expect(sortables).toHaveLength(1);

    choose(input, [file("a.png"), file("b.png")]);
    const positions = [
      ...preview.querySelectorAll("[data-file-upload-position]"),
    ].map((p) => p.value);
    expect(positions).toEqual(["0", "1", "2"]);
  });

  it("renumbers after a delete and after a drag", () => {
    const { input, preview } = setup(attrs, {
      inputAttrs:
        'data-file-upload-prefix="repo[photos_attributes]" data-file-upload-suffix="image"',
    });
    choose(input, [file("a.png"), file("b.png"), file("c.png")]);
    items(preview)[0].querySelector(".file-upload-item-delete").click();

    const positions = () =>
      [...preview.querySelectorAll("[data-file-upload-position]")].map(
        (p) => p.value,
      );
    expect(positions()).toEqual(["0", "1"]);

    preview.append(items(preview)[0]);
    sortables[0].options.onEnd();
    expect(positions()).toEqual(["0", "1"]);
  });

  it("renumbers when an existing item is marked for removal", () => {
    const row = (n, p) => `<div class="file-upload-item-preview">
      <input type="hidden" data-file-upload-position value="${p}">
      <input type="hidden" data-file-upload-hidden-destroy value="false">
      <button type="button" data-file-upload-item-delete id="d${n}"></button></div>`;
    const { preview } = setup({ ...attrs, items: row(1, 0) + row(2, 1) });
    document.getElementById("d1").click();
    const visible = items(preview).filter((r) => !r.hidden);
    expect(visible[0].querySelector("[data-file-upload-position]").value).toBe(
      "0",
    );
  });

  it("gives a sortable item without a nested suffix no position field", () => {
    const { input, preview } = setup(attrs);
    choose(input, [file("a.png")]);
    expect(
      preview.querySelector("input[type=hidden][name$='[position]']"),
    ).toBeNull();
  });
});

describe("drop zone", () => {
  const drag = (zone, type, { types = ["Files"], files = [] } = {}) => {
    const event = new Event(type, { cancelable: true });
    event.dataTransfer = { types, files, dropEffect: "" };
    zone.dispatchEvent(event);
    return event;
  };

  it("highlights while files are dragged over and clears on leave", () => {
    const { zone } = setup({});
    drag(zone, "dragenter");
    drag(zone, "dragenter");
    expect(zone.classList.contains("file-upload-drop-active")).toBe(true);
    drag(zone, "dragleave");
    expect(zone.classList.contains("file-upload-drop-active")).toBe(true);
    drag(zone, "dragleave");
    expect(zone.classList.contains("file-upload-drop-active")).toBe(false);
  });

  it("accepts a copy drop only for files", () => {
    const { zone } = setup({});
    const over = drag(zone, "dragover");
    expect(over.defaultPrevented).toBe(true);
    expect(over.dataTransfer.dropEffect).toBe("copy");

    const text = drag(zone, "dragover", { types: ["text/plain"] });
    expect(text.defaultPrevented).toBe(false);
    drag(zone, "dragenter", { types: ["text/plain"] });
    expect(zone.classList.contains("file-upload-drop-active")).toBe(false);
    drag(zone, "dragleave", { types: ["text/plain"] });
  });

  it("adds dropped files to the preview", () => {
    const { zone, preview } = setup({});
    drag(zone, "drop", { files: [file("a.png"), file("b.png")] });
    expect(items(preview)).toHaveLength(2);
    expect(zone.classList.contains("file-upload-drop-active")).toBe(false);
  });

  it("ignores a drop without files", () => {
    const { zone, preview } = setup({});
    const event = drag(zone, "drop", { types: [], files: [] });
    expect(event.defaultPrevented).toBe(false);
    expect(items(preview)).toHaveLength(0);
  });

  const names = (preview) =>
    items(preview).map((r) => r.querySelector("span").textContent);

  it("skips dropped files the input does not accept", () => {
    const { zone, preview, input } = setup(
      {},
      {
        inputAttrs:
          'data-file-upload-prefix="repo[photos]" accept="image/*,.pdf,application/zip"',
      },
    );
    expect(input.accept).toContain("image/*");
    drag(zone, "drop", {
      files: [
        file("a.png"),
        file("notes.txt", "text/plain"),
        file("doc.PDF", "application/pdf"),
        file("z.zip", "application/zip"),
      ],
    });
    expect(names(preview)).toEqual(["a.png", "doc.PDF", "z.zip"]);
  });

  it("stops dropped files at the limit", () => {
    const { zone, preview } = setup(
      {},
      {
        inputAttrs:
          'data-file-upload-prefix="repo[photos]" data-file-upload-limit="2"',
      },
    );
    drag(zone, "drop", {
      files: [file("a.png"), file("b.png"), file("c.png")],
    });
    expect(names(preview)).toEqual(["a.png", "b.png"]);
  });

  it("does not count a rejected dropped file towards the limit", () => {
    const { zone, preview } = setup(
      {},
      {
        inputAttrs:
          'data-file-upload-prefix="repo[photos]" data-file-upload-limit="2" accept="image/*"',
      },
    );
    drag(zone, "drop", {
      files: [file("a.png"), file("notes.txt", "text/plain"), file("c.png")],
    });
    expect(names(preview)).toEqual(["a.png", "c.png"]);
  });
});

describe("setup problems", () => {
  it("warns when no prefix can be found", () => {
    document.body.innerHTML = `<input type="file" data-file-upload-helper data-file-upload-preview-selector="#p"><div id="p"></div>`;
    document.dispatchEvent(new Event("turbo:load"));
    expect(console.warn).toHaveBeenCalledWith(
      "file_upload: data-file-upload-prefix is required on",
      expect.anything(),
    );
  });

  it("warns when the preview pane is missing", () => {
    document.body.innerHTML = `<input type="file" data-file-upload-helper data-file-upload-prefix="x" data-file-upload-preview-selector="#nope">`;
    document.dispatchEvent(new Event("turbo:load"));
    expect(console.warn).toHaveBeenCalledWith(
      "file_upload: preview pane not found for selector #nope",
    );
  });

  it("sets an input up only once", () => {
    const { input, preview } = setup({});
    document.dispatchEvent(new Event("turbo:load"));
    choose(input, [file("a.png")]);
    expect(items(preview)).toHaveLength(1);
  });
});
