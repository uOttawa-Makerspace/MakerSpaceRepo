import { showToast } from "./toast";

// What the user is told when a request fails. The layout renders the translated texts as data attributes of
// the <html> element (see ApplicationHelper#request_text_attributes).
export function pageText(name) {
  return document.documentElement.dataset[name] ?? "";
}

// The JSON body of a response, or null when the text is not JSON (an HTML error page, an empty body).
export function parseBody(text) {
  try {
    return JSON.parse(text);
  } catch {
    return null;
  }
}

// What to tell the user about a failed request: the server's `error`, followed by its
// `reference` (the code staff search the logs for) unless the text already quotes it.
// `fallback` is the translated text for a response that carried no reason.
export function serverError(body, fallback) {
  const message = body?.error;
  if (typeof message !== "string" || message === "") return fallback;
  const reference = body.reference;
  return reference && !message.includes(reference)
    ? `${message} [${reference}]`
    : message;
}

// An error whose message is already translated text for the user, never a browser exception message.
export class RequestFailed extends Error {}

// Sends the request and reads the whole answer: { ok, contentType, text, requestId }. When the request or the
// reading of its body fails (server unreachable, connection dropped), throws a RequestFailed carrying
// `networkText` (the page's translated text unless given).
export async function requestResult(
  input,
  init,
  networkText = pageText("requestNetwork"),
) {
  try {
    const response = await fetch(input, init);
    return {
      ok: response.ok,
      contentType: response.headers?.get("content-type") ?? "",
      requestId: response.headers?.get("X-Request-Id") ?? "",
      text: await response.text(),
    };
  } catch {
    throw new RequestFailed(networkText);
  }
}

// The reason a failed answer gives: the server's own `error`, otherwise `fallback` (the page's generic text
// unless given) followed by the first characters of the request id when the answer carried one.
export function resultError(
  { text, requestId },
  fallback = pageText("requestFailed"),
) {
  const generic = requestId
    ? `${fallback} [${requestId.slice(0, 8)}]`
    : fallback;
  return serverError(parseBody(text), generic);
}

// Sends the request and returns its parsed JSON body (null for an empty or non-JSON body). A failed answer,
// or an OK one with no JSON body when `requireBody` is set, throws a RequestFailed with the reason to show.
export async function requestJson(
  input,
  init,
  { fallback, networkText, requireBody = false } = {},
) {
  const result = await requestResult(input, init, networkText);
  const body = parseBody(result.text);
  if (result.ok && !(requireBody && body === null)) return body;
  throw new RequestFailed(resultError(result, fallback));
}

// Sends the request and returns the answer's text. A failed answer throws a RequestFailed with the reason to show.
export async function requestText(input, init, options = {}) {
  const result = await requestResult(input, init, options.networkText);
  if (!result.ok)
    throw new RequestFailed(resultError(result, options.fallback));
  return result.text;
}

// The text to show for any error caught by a caller of the helpers above: its own message when it is a
// RequestFailed, otherwise `fallback` (the page's generic text unless given).
export function failureText(error, fallback = pageText("requestFailed")) {
  return error instanceof RequestFailed ? error.message : fallback;
}

// Shows `message` as an error toast.
export function showFailure(message) {
  showToast(message, { type: "error" });
}

// Shows the failure as an error toast. An error that is not a RequestFailed (a bug in the page's own code)
// is also logged, since its message is not shown.
export function reportFailure(error) {
  if (!(error instanceof RequestFailed)) console.error(error);
  showFailure(failureText(error));
}
