# Free hosting backup (if Vercel pauses the site)

The game is a static Vite site (about 6 MB) and all game data lives in Supabase, so any static host works.
`wrangler.jsonc` (single-page-app fallback) and `public/_headers` (cache rules) are already set up
(Vercel ignores them; `vercel.json` stays as is).

## Cloudflare Pages (free, no card, very generous traffic)
1. dash.cloudflare.com -> Workers & Pages -> Create -> Pages -> Connect to Git -> pick `dev-shalom/benin-life`, branch `main`.
2. Build command `npm run build`, output folder `dist`.
3. Add the same environment variables that Vercel has (the VITE_* ones: Supabase URL, anon key, etc.).
4. Deploy. You get a `*.pages.dev` link to test.
5. When it works, Pages -> Custom domains -> add `playbeninlife.app` and follow the DNS steps at your domain registrar.
6. In Supabase -> Authentication -> URL configuration, add the new address to the allowed redirect URLs if you test on the `pages.dev` link.
