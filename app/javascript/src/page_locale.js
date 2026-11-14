import { French } from "flatpickr/dist/esm/l10n/fr.js";

// The language of the page a widget is drawn on, and the widget texts the
// layout renders beside it on the <html> element (data-widget-texts, from
// config/locales/widgets-*.yml; see ApplicationHelper#request_text_attributes).
// The target is the widget's element, or the document for a widget started
// from a selector. A page without the texts keeps each library's own English.

function pageRoot(target) {
  return (target.ownerDocument ?? target).documentElement;
}

export function pageLanguage(target) {
  return pageRoot(target).lang;
}

function widgetTexts(target) {
  return JSON.parse(pageRoot(target).dataset.widgetTexts ?? "{}");
}

// DataTables options with its texts in the page's language; a language the
// options give (a search placeholder) is kept over them.
export function dataTableOptions(target, options = {}) {
  const language = widgetTexts(target).datatables;
  if (!language) return options;
  return { ...options, language: { ...language, ...options.language } };
}

// flatpickr's own French on a French page, with Sunday first like the site's
// calendars. `altFormat` names the format of the shown date (date or
// date_time), which the page's language words.
const FLATPICKR_LOCALES = { fr: { ...French, firstDayOfWeek: 0 } };

export function flatpickrOptions(target, options = {}, altFormat = null) {
  const locale = FLATPICKR_LOCALES[pageLanguage(target)] ?? "default";
  const format = widgetTexts(target).flatpickr?.[altFormat];
  return { ...options, locale, ...(format && { altFormat: format }) };
}

// The plugins whose title the page words, and the data attribute of the select
// that may give its own (data-remove-title="Remove skill").
const PLUGIN_TITLES = {
  remove_button: ["removeTitle", "remove"],
  clear_button: ["clearTitle", "clear_all"],
};

function pluginTitle(target, name, texts) {
  const [attribute, key] = PLUGIN_TITLES[name] ?? [];
  if (!key) return {};
  return { title: target.dataset?.[attribute] ?? texts[key] };
}

function titledPlugins(target, plugins, texts) {
  const entries = Array.isArray(plugins)
    ? plugins.map((name) => [name, {}])
    : Object.entries(plugins);
  return Object.fromEntries(
    entries.map(([name, settings]) => [
      name,
      { ...pluginTitle(target, name, texts), ...settings },
    ]),
  );
}

function textBlock(target, className, text) {
  const block = pageRoot(target).ownerDocument.createElement("div");
  block.className = className;
  block.textContent = text;
  return block;
}

function createOption(target, texts, input) {
  const block = textBlock(target, "create", `${texts.add} `);
  const typed = block.ownerDocument.createElement("strong");
  typed.textContent = input;
  block.append(typed, "…");
  return block;
}

// Tom Select options with its texts (no results, add, remove, clear) in the
// page's language; a render function or plugin title the options give is kept.
export function tomSelectOptions(target, options = {}) {
  const texts = widgetTexts(target).tom_select;
  if (!texts) return options;
  return {
    ...options,
    render: {
      no_results: () => textBlock(target, "no-results", texts.no_results),
      option_create: (data) => createOption(target, texts, data.input),
      ...options.render,
    },
    plugins: titledPlugins(target, options.plugins ?? [], texts),
  };
}
