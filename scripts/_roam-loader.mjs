// Shared node loader for the roam scripts (same trick as scripts/city-check.mjs): resolve extensionless TS imports, JSON as modules.
import { register } from 'node:module';

register(
  'data:text/javascript,' +
    encodeURIComponent(`
export async function resolve(spec, ctx, next) {
  if ((spec.startsWith('./') || spec.startsWith('../')) && !/\\.[cm]?[jt]sx?$|\\.json$/.test(spec)) {
    try { return await next(spec + '.ts', ctx); } catch {}
  }
  return next(spec, ctx);
}
export async function load(url, ctx, next) {
  if (url.endsWith('.json')) {
    const { readFile } = await import('node:fs/promises');
    const { fileURLToPath } = await import('node:url');
    return { format: 'module', shortCircuit: true, source: 'export default ' + (await readFile(fileURLToPath(url), 'utf8')) };
  }
  return next(url, ctx);
}`),
  import.meta.url,
);
