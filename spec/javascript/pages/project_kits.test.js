// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

await import("../../../app/javascript/entrypoints/project_kits.js");

const answer = (body) => vi.fn(async () => new Response(JSON.stringify(body)));

// Types the query into the picker's search box and waits out its input and
// load throttles.
function type(select, query) {
  const input = select.tomselect.control_input;
  input.value = query;
  input.dispatchEvent(new Event("input"));
  const { refreshThrottle, loadThrottle } = select.tomselect.settings;
  vi.advanceTimersByTime(refreshThrottle + loadThrottle);
}

afterEach(() => {
  vi.useRealTimers();
  document.body.innerHTML = "";
});

describe("kit user picker", () => {
  const picker = (fetchMock) => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", fetchMock);
    document.body.innerHTML = `<select id="kit_user_select"></select>`;
    document.dispatchEvent(new Event("turbo:load"));
    return document.getElementById("kit_user_select");
  };

  it.each(["a", "ab"])("does not search for %j", (query) => {
    const fetchMock = answer({ users: [] });
    type(picker(fetchMock), query);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("searches once three characters are typed, offering each user's name", async () => {
    const fetchMock = answer({ users: [{ id: 4, name: "Ann Lee" }] });
    const select = picker(fetchMock);
    type(select, "ann");
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      "/project_kits/populate_kit_users?search=ann",
    ]);
    await vi.waitFor(() =>
      expect(select.tomselect.options["4"]).toMatchObject({
        id: 4,
        name: "Ann Lee",
      }),
    );
  });
});
