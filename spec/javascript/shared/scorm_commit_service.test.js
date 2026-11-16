// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { ScormCommitService } from "../../../app/javascript/src/scorm_commit_service.js";

class FakeXhr {
  static instances = [];
  static status = 200;
  static throwOnSend = false;
  constructor() {
    this.headers = {};
    FakeXhr.instances.push(this);
  }
  open(method, url, async) {
    Object.assign(this, { method, url, async });
  }
  setRequestHeader(name, value) {
    this.headers[name] = value;
  }
  getResponseHeader() {
    return null;
  }
  send(body) {
    if (FakeXhr.throwOnSend) throw new Error("refused");
    this.body = body;
    this.status = FakeXhr.status;
    this.responseText = "";
  }
}

beforeEach(() => {
  FakeXhr.instances = [];
  FakeXhr.status = 200;
  FakeXhr.throwOnSend = false;
  vi.stubGlobal("XMLHttpRequest", FakeXhr);
  document.head.innerHTML =
    '<meta name="csrf-token" content="tok"><meta name="csrf-param" content="authenticity_token">';
});

afterEach(() => vi.unstubAllGlobals());

const params = { cmi: { suspend_data: "abc" } };
const stubBeacon = (impl) =>
  vi.stubGlobal("navigator", { ...navigator, sendBeacon: impl });

describe("regular commit", () => {
  it("posts the data synchronously as JSON with the token and reports success", () => {
    const service = new ScormCommitService();
    const result = service.processHttpRequest("/commit", params);

    const xhr = FakeXhr.instances[0];
    expect(xhr).toMatchObject({ method: "POST", url: "/commit", async: false });
    expect(xhr.headers).toMatchObject({
      "Content-Type": "application/json;charset=UTF-8",
      Accept: "application/json",
      "X-CSRF-Token": "tok",
    });
    expect(JSON.parse(xhr.body)).toEqual(params);
    expect(result).toEqual({ result: "true", errorCode: 0 });
  });

  it("reports failure for a non 2xx status with the configured code", () => {
    FakeXhr.status = 500;
    expect(
      new ScormCommitService({ commitFailureCode: 391 }).processHttpRequest(
        "/c",
        params,
      ),
    ).toEqual({ result: "false", errorCode: 391 });
  });

  it("uses code 101 by default", () => {
    FakeXhr.status = 404;
    expect(
      new ScormCommitService().processHttpRequest("/c", params).errorCode,
    ).toBe(101);
  });

  it("reports failure when the request cannot be sent", () => {
    FakeXhr.throwOnSend = true;
    expect(
      new ScormCommitService().processHttpRequest("/c", params).result,
    ).toBe("false");
  });

  it("accepts settings updates without effect", () => {
    expect(new ScormCommitService().updateSettings({})).toBeUndefined();
  });
});

describe("terminate commit", () => {
  it("queues a JSON beacon carrying the token in the body", async () => {
    const beacon = vi.fn(() => true);
    stubBeacon(beacon);
    const result = new ScormCommitService().processHttpRequest(
      "/c",
      params,
      true,
    );

    expect(result.result).toBe("true");
    expect(FakeXhr.instances).toHaveLength(0);
    const [url, blob] = beacon.mock.calls[0];
    expect(url).toBe("/c");
    expect(blob.type).toBe("application/json");
    expect(JSON.parse(await blob.text())).toEqual({
      ...params,
      authenticity_token: "tok",
    });
  });

  it("falls back to a synchronous request when the beacon is not queued", () => {
    stubBeacon(() => false);
    const result = new ScormCommitService().processHttpRequest(
      "/c",
      params,
      true,
    );
    expect(FakeXhr.instances).toHaveLength(1);
    expect(result.result).toBe("true");
  });

  it("falls back when the browser refuses the beacon", () => {
    stubBeacon(() => {
      throw new Error("SecurityError");
    });
    new ScormCommitService().processHttpRequest("/c", params, true);
    expect(FakeXhr.instances).toHaveLength(1);
  });

  it("skips the beacon for data over the beacon quota", () => {
    const beacon = vi.fn(() => true);
    stubBeacon(beacon);
    const big = { cmi: { suspend_data: "x".repeat(61 * 1024) } };
    new ScormCommitService().processHttpRequest("/c", big, true);
    expect(beacon).not.toHaveBeenCalled();
    expect(FakeXhr.instances).toHaveLength(1);
  });
});
