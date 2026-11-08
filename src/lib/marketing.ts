// Which URLs are the marketing pages (graphite and bronze look, docs/FRONTEND.md). Keep in sync with the inline
// script in index.html, which sets the page colours before first paint.
export function isMarketingPath(path: string): boolean {
  return path === '/' || path === '/auth' || path === '/terms' || path === '/privacy' || path.startsWith('/c/');
}
