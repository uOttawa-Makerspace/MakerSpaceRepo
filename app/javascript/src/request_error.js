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

// Sends the request and reads the whole answer: { ok, contentType, text }. When the request or the reading of
// its body fails (server unreachable, connection dropped), throws a RequestFailed carrying `networkText`.
export async function requestResult(input, init, networkText) {
  try {
    const response = await fetch(input, init);
    return {
      ok: response.ok,
      contentType: response.headers?.get("content-type") ?? "",
      text: await response.text(),
    };
  } catch {
    throw new RequestFailed(networkText);
  }
}

// The text to show for any error caught by a caller of requestResult: its own message when it is a
// RequestFailed, otherwise `fallback`.
export function failureText(error, fallback) {
  return error instanceof RequestFailed ? error.message : fallback;
}
