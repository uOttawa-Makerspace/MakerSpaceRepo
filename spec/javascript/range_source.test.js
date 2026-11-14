import { describe, expect, it, vi } from "vitest";
import { rangeSource, unticked } from "../../app/javascript/src/range_source";

const range = (startStr, endStr) => ({ startStr, endStr });

const answer = (status, body) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

// Calls the source's events function and settles with what it hands to
// success or failure.
const draw = (source, info) =>
  new Promise((resolve) => {
    source.events(
      info,
      (rows) => resolve({ rows }),
      (error) => resolve({ error }),
    );
  });

const week = range("2026-11-09", "2026-11-16");
const nextWeek = range("2026-11-16", "2026-11-23");

describe("rangeSource", () => {
  it("keeps its id", () => {
    expect(
      rangeSource(
        "hours",
        "/feed",
        (r) => r,
        (r) => r,
      ).id,
    ).toBe("hours");
  });

  it("asks the feed for the range as JSON and draws the rows it keeps", async () => {
    const fetch = vi.fn(async () => answer(200, { items: [1, 2, 3] }));
    vi.stubGlobal("fetch", fetch);
    const source = rangeSource(
      "hours",
      "/feed",
      (body) => body.items,
      (rows) => rows.filter((row) => row !== 2),
    );

    expect(await draw(source, week)).toEqual({ rows: [1, 3] });
    expect(fetch).toHaveBeenCalledWith(
      "/feed?start=2026-11-09&end=2026-11-16",
      { headers: { Accept: "application/json" } },
    );
  });

  it("asks once per range, and again for a new range", async () => {
    const fetch = vi.fn(async () => answer(200, [1]));
    vi.stubGlobal("fetch", fetch);
    let keep = (rows) => rows;
    const source = rangeSource(
      "hours",
      "/feed",
      (r) => r,
      (rows) => keep(rows),
    );

    await draw(source, week);
    keep = () => [];
    expect(await draw(source, week)).toEqual({ rows: [] });
    expect(fetch).toHaveBeenCalledTimes(1);

    await draw(source, nextWeek);
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("reports a failed answer and asks again on the next redraw", async () => {
    const fetch = vi
      .fn()
      .mockResolvedValueOnce(answer(500, {}))
      .mockResolvedValueOnce(answer(200, [7]));
    vi.stubGlobal("fetch", fetch);
    const source = rangeSource(
      "hours",
      "/feed",
      (r) => r,
      (r) => r,
    );

    const failed = await draw(source, week);
    expect(failed.error).toBeInstanceOf(Error);
    expect(failed.error.message).toBe("/feed answered 500");

    expect(await draw(source, week)).toEqual({ rows: [7] });
    expect(fetch).toHaveBeenCalledTimes(2);
  });

  it("forgets a request that could not be sent", async () => {
    const fetch = vi
      .fn()
      .mockRejectedValueOnce(new TypeError("offline"))
      .mockResolvedValueOnce(answer(200, [8]));
    vi.stubGlobal("fetch", fetch);
    const source = rangeSource(
      "hours",
      "/feed",
      (r) => r,
      (r) => r,
    );

    expect((await draw(source, week)).error.message).toBe("offline");
    expect(await draw(source, week)).toEqual({ rows: [8] });
  });
});

describe("unticked", () => {
  it("gives the values of the boxes that are not checked", () => {
    const boxes = [
      { checked: true, value: "a" },
      { checked: false, value: "b" },
      { checked: false, value: "c" },
    ];

    expect(unticked(boxes)).toEqual(new Set(["b", "c"]));
  });

  it("is empty when every box is checked", () => {
    expect(unticked([{ checked: true, value: "a" }])).toEqual(new Set());
  });
});
