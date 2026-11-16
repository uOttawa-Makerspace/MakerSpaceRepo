// @vitest-environment happy-dom
import { afterEach, describe, expect, it } from "vitest";
import DataTable from "datatables.net-bs5";
import TomSelect from "tom-select";
import flatpickr from "flatpickr";

import {
  dataTableOptions,
  flatpickrOptions,
  pageLanguage,
  tomSelectOptions,
} from "../../app/javascript/src/page_locale.js";

// The widget texts the layout renders on <html> (config/locales/widgets-*.yml),
// as far as these examples read them.
const TEXTS = {
  en: {
    datatables: {
      info: "Showing _START_ to _END_ of _TOTAL_ _ENTRIES-TOTAL_",
      search: "Search:",
      entries: { _: "entries", 1: "entry" },
    },
    flatpickr: { date: "F j, Y", date_time: "F j, Y at H:i" },
    tom_select: {
      add: "Add",
      clear_all: "Clear All",
      no_results: "No results found",
      remove: "Remove",
    },
  },
  fr: {
    datatables: {
      info: "Affichage de _START_ à _END_ sur _TOTAL_ _ENTRIES-TOTAL_",
      search: "Rechercher :",
      entries: { _: "entrées", 1: "entrée" },
    },
    flatpickr: { date: "J F Y", date_time: "J F Y à H:i" },
    tom_select: {
      add: "Ajouter",
      clear_all: "Tout effacer",
      no_results: "Aucun résultat",
      remove: "Retirer",
    },
  },
};

function page(lang, texts = TEXTS[lang], body = "") {
  const root = document.documentElement;
  root.setAttribute("lang", lang);
  if (texts) root.dataset.widgetTexts = JSON.stringify(texts);
  else delete root.dataset.widgetTexts;
  document.body.innerHTML = body;
}

const cleanups = [];
afterEach(() => {
  cleanups.splice(0).forEach((cleanup) => cleanup());
  document.body.innerHTML = "";
});

describe("pageLanguage", () => {
  it("reads the language of the element's own document", () => {
    page("fr", null, `<p id="p"></p>`);
    expect(pageLanguage(document.getElementById("p"))).toBe("fr");
    expect(pageLanguage(document)).toBe("fr");
  });
});

describe("with no options given", () => {
  it("gives each library only the page's texts", () => {
    page("en");
    expect(dataTableOptions(document).language.search).toBe("Search:");
    expect(flatpickrOptions(document)).toEqual({ locale: "default" });
    expect(tomSelectOptions(document).plugins).toEqual({});
  });
});

describe("dataTableOptions", () => {
  const TABLE = `<table id="t"><thead><tr><th>Name</th></tr></thead>
    <tbody><tr><td>Ada</td></tr><tr><td>Grace</td></tr></tbody></table>`;

  // happy-dom has no Option constructor, which the page length menu needs.
  function draw(lang, texts = TEXTS[lang]) {
    page(lang, texts, TABLE);
    const table = document.getElementById("t");
    const options = dataTableOptions(table, { lengthChange: false });
    const dt = new DataTable(table, options);
    cleanups.push(() => dt.destroy());
    const text = (selector) =>
      table.closest(".dt-container").querySelector(selector).textContent;
    return { info: text(".dt-info"), search: text(".dt-search label") };
  }

  it("words the table in English on an English page", () => {
    expect(draw("en")).toEqual({
      info: "Showing 1 to 2 of 2 entries",
      search: "Search:",
    });
  });

  it("words the table in French on a French page", () => {
    expect(draw("fr")).toEqual({
      info: "Affichage de 1 à 2 sur 2 entrées",
      search: "Rechercher :",
    });
  });

  it("keeps a language the options give", () => {
    page("fr");
    const options = dataTableOptions(document, {
      pageLength: 5,
      language: { searchPlaceholder: "Casier" },
    });
    expect(options.pageLength).toBe(5);
    expect(options.language.searchPlaceholder).toBe("Casier");
    expect(options.language.search).toBe("Rechercher :");
  });

  it("leaves the library's English on a page without the texts", () => {
    expect(draw("fr", null).info).toBe("Showing 1 to 2 of 2 entries");
  });
});

describe("flatpickrOptions", () => {
  function pick(lang, altFormat, options = {}) {
    page(lang, TEXTS[lang], `<input id="d" value="2026-11-01 09:30">`);
    const input = document.getElementById("d");
    const picker = flatpickr(
      input,
      flatpickrOptions(
        input,
        { enableTime: true, altInput: true, ...options },
        altFormat,
      ),
    );
    cleanups.push(() => picker.destroy());
    return picker;
  }

  it("names the months in English and shows the English format", () => {
    const picker = pick("en", "date_time");
    expect(picker.l10n.months.longhand[10]).toBe("November");
    expect(picker.altInput.value).toBe("November 1, 2026 at 09:30");
    expect(picker.config.locale).toBe("default");
  });

  it("names the months in French and shows the French format", () => {
    const picker = pick("fr", "date_time");
    expect(picker.l10n.months.longhand[10]).toBe("novembre");
    expect(picker.altInput.value).toBe("1er novembre 2026 à 09:30");
  });

  it("starts the French week on Sunday like the site's calendars", () => {
    expect(pick("fr", "date").l10n.firstDayOfWeek).toBe(0);
  });

  it("keeps the options' own format when none is named", () => {
    const picker = pick("fr", null, { altFormat: "Y" });
    expect(picker.altInput.value).toBe("2026");
  });
});

describe("tomSelectOptions", () => {
  function select(lang, options = {}, attributes = "") {
    page(
      lang,
      TEXTS[lang],
      `<select id="s" ${attributes} multiple><option value="1" selected>Ada</option></select>`,
    );
    const el = document.getElementById("s");
    const ts = new TomSelect(el, tomSelectOptions(el, options));
    cleanups.push(() => ts.destroy());
    return ts;
  }

  function noResults(ts) {
    ts.setTextboxValue("zzz");
    ts.refreshOptions(true);
    return ts.dropdown_content.textContent;
  }

  it("words its own texts in English on an English page", () => {
    const ts = select("en", { plugins: ["remove_button"], create: true });
    expect(ts.wrapper.querySelector(".remove").title).toBe("Remove");
    ts.setTextboxValue("Lin");
    ts.refreshOptions(true);
    expect(ts.dropdown_content.querySelector(".create").innerHTML).toBe(
      "Add <strong>Lin</strong>…",
    );
    expect(noResults(select("en"))).toBe("No results found");
  });

  it("words its own texts in French on a French page", () => {
    const ts = select("fr", {
      plugins: { remove_button: {}, clear_button: {} },
    });
    expect(ts.wrapper.querySelector(".remove").title).toBe("Retirer");
    expect(ts.wrapper.querySelector(".clear-button").title).toBe(
      "Tout effacer",
    );
    expect(noResults(ts)).toBe("Aucun résultat");
  });

  it("words the typed text to add in French, as text", () => {
    const ts = select("fr", { create: true });
    ts.setTextboxValue("<b>Lin</b>");
    ts.refreshOptions(true);
    const create = ts.dropdown_content.querySelector(".create");
    expect(create.textContent).toBe("Ajouter <b>Lin</b>…");
    expect(create.querySelector("b")).toBeNull();
  });

  it("takes a button title the select gives", () => {
    const ts = select(
      "fr",
      { plugins: ["remove_button"] },
      'data-remove-title="Retirer la compétence"',
    );
    expect(ts.wrapper.querySelector(".remove").title).toBe(
      "Retirer la compétence",
    );
  });

  it("keeps a render function and plugin title the options give", () => {
    page("fr");
    const own = () => "mine";
    const options = tomSelectOptions(document, {
      render: { no_results: own },
      plugins: { remove_button: { title: "Ôter" }, checkbox_options: {} },
    });
    expect(options.render.no_results).toBe(own);
    expect(options.plugins).toEqual({
      remove_button: { title: "Ôter" },
      checkbox_options: {},
    });
  });

  it("leaves the library's own texts on a page without the texts", () => {
    page("fr", null);
    const options = { plugins: ["remove_button"] };
    expect(tomSelectOptions(document, options)).toBe(options);
  });
});
