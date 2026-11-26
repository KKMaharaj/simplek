export function escapeHtml(s: unknown): string {
  return String(s ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
export const TZ = 'Asia/Kolkata';
const IST_OFFSET_MIN = 330;

/** Calendar parts of a date as seen in India. */
export function istParts(d: Date) {
  const shifted = new Date(d.getTime() + IST_OFFSET_MIN * 60000);
  return { y: shifted.getUTCFullYear(), m: shifted.getUTCMonth() + 1, d: shifted.getUTCDate() };
}

/** Midnight IST of the given IST calendar day, as a UTC Date. */
