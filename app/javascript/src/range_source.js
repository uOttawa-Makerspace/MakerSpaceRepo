// The rows of a feed for the calendar's range (?start&end).
async function fetchRange(url, info) {
  const range = new URLSearchParams({ start: info.startStr, end: info.endStr });
  const response = await fetch(`${url}?${range}`, {
    headers: { Accept: "application/json" },
  });
  if (!response.ok) throw new Error(`${url} answered ${response.status}`);
  return response.json();
}

// A calendar source that asks the feed once per range and draws the rows
// `visible` keeps, so a filter checkbox redraws without asking again. A failed
// request is forgotten, so the next redraw asks again; `forget` drops the rows
// too, for when the feed has changed.
export function rangeSource(id, url, rowsOf, visible) {
  let fetched = { range: null, rows: Promise.resolve([]) };
  return {
    id,
    forget: () => (fetched.range = null),
    events: (info, success, failure) => {
      const range = `${info.startStr}/${info.endStr}`;
      if (fetched.range !== range) {
        const asked = { range, rows: fetchRange(url, info).then(rowsOf) };
        asked.rows.catch(() => (asked.range = null));
        fetched = asked;
      }
      fetched.rows.then((rows) => success(visible(rows)), failure);
    },
  };
}

// The values of the unticked boxes.
export const unticked = (boxes) =>
  new Set(boxes.filter((box) => !box.checked).map((box) => box.value));
