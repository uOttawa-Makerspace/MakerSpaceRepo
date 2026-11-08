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
