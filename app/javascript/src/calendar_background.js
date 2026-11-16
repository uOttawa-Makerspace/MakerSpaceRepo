const COLOR = "#(?:[0-9a-f]{3}|[0-9a-f]{6})";
const STOP = `${COLOR} \\d+(?:\\.\\d+)?%, ${COLOR} \\d+(?:\\.\\d+)?%`;
const BACKGROUND = new RegExp(
  `^(?:${COLOR}|linear-gradient\\(to right, ${STOP}(?:, ${STOP})*\\);(?: opacity: 0\\.8;)?)$`,
  "i",
);

const HEX_COLOUR = /^#[0-9a-f]{3}(?:[0-9a-f]{3})?$/i;

/** True for a #rgb or #rrggbb colour and nothing else. */
export function isHexColour(colour) {
  return typeof colour === "string" && HEX_COLOUR.test(colour);
}

/**
 * Sets the event's background from the server-built value: a hex colour, or the
 * staff colour gradient. Any other value is ignored, so the calendar's default
 * colour shows and no other CSS can ride in on the style attribute.
 */
export function applyEventBackground(element, background) {
  if (BACKGROUND.test(background)) {
    element.setAttribute("style", `background: ${background}`);
  }
}
