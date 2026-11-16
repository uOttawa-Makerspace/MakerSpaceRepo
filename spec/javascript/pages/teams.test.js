// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";

await import("../../../app/javascript/entrypoints/teams.js");

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

describe("team captain picker", () => {
  const picker = (fetchMock) => {
    vi.useFakeTimers();
    vi.stubGlobal("fetch", fetchMock);
    document.body.innerHTML = `<select id="search_users_add"></select>`;
    document.dispatchEvent(new Event("turbo:load"));
    return document.getElementById("search_users_add");
  };

  it.each(["a", "ab"])("does not search for %j", (query) => {
    const fetchMock = answer({ users: [] });
    type(picker(fetchMock), query);
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("searches once three characters are typed, offering name and username", async () => {
    const fetchMock = answer({
      users: [{ id: 4, username: "ann", name: "Ann Lee" }],
    });
    const select = picker(fetchMock);
    type(select, "ann");
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual([
      "/repositories/populate_users?search=ann",
    ]);
    await vi.waitFor(() =>
      expect(select.tomselect.options["4"]).toMatchObject({
        id: 4,
        username: "Ann Lee (ann)",
      }),
    );
  });
});
