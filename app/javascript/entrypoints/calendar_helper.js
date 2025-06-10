/*
 * Converts a Date object to a local datetime string in the format YYYY-MM-DDTHH:MM
 * If the value is empty, it returns null.
 */
export function toLocalDatetimeString(date) {
  if (!date) return null;

  const pad = (n) => (n < 10 ? "0" + n : n);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

/*
 * Converts a Date object to a local date string in the format YYYY-MM-DD
 * If the value is empty, it returns null.
 */
export function toLocalDateString(date) {
  if (!date) return null;

  const pad = (n) => (n < 10 ? "0" + n : n);
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
}

/*
 * Parses a local datetime string in the format YYYY-MM-DDTHH:MM
 * and returns a Date object.
 * If the value is empty, it returns the current date.
 */
export function parseLocalDatetimeString(value) {
  if (!value) return new Date();
  return new Date(value);
}
