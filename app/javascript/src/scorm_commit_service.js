import { csrfHeaders, csrfParam, csrfToken } from "./csrf";

const SUCCESS = { result: "true", errorCode: 0 };
const FAILURE = { result: "false", errorCode: 101 };

// scorm-again's HTTP service for commits to this app (settings.httpService).
// - Regular commits: a synchronous XHR, as scorm-again's own SCORM-compliant
//   service does (the SCO learns whether the commit worked): a JSON body with
//   the CSRF header (csrfHeaders).
// - The terminate commit (immediate: the page is closing): a beacon. scorm-again
//   sends it as text/plain, which Rails neither parses nor CSRF-checks, so the
//   final state was lost. Here it is an application/x-www-form-urlencoded body
//   carrying the CSRF token field, which Rails parses and checks.
export class ScormCommitService {
  updateSettings() {}

  processHttpRequest(url, params, immediate = false) {
    return immediate ? this.beacon(url, params) : this.post(url, params);
  }

  post(url, params) {
    const xhr = new XMLHttpRequest();
    xhr.open("POST", url, false);
    const headers = csrfHeaders({
      "Content-Type": "application/json;charset=UTF-8",
      Accept: "application/json",
    });
    Object.entries(headers).forEach(([name, value]) => xhr.setRequestHeader(name, value));
    try {
      xhr.send(JSON.stringify(params));
    } catch (e) {
      return FAILURE;
    }
    return xhr.status >= 200 && xhr.status <= 299 ? SUCCESS : FAILURE;
  }

  beacon(url, params) {
    const body = new URLSearchParams();
    body.append(csrfParam(), csrfToken());
    Object.entries(params || {}).forEach(([key, value]) => {
      if (value !== null && value !== undefined && typeof value !== "object") {
        body.append(key, String(value));
      }
    });
    const sent = navigator.sendBeacon(
      url,
      new Blob([body.toString()], { type: "application/x-www-form-urlencoded" }),
    );
    return sent ? SUCCESS : FAILURE;
  }
}
