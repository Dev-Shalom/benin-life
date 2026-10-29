# SEO (search engine optimization)

Goal: people who search "Benin Life", "who owns Benin Life" or "Benin City game" find playbeninlife.app, and see **Shalom Uwagboe** as the creator and owner.

## What is in the code (28 Oct 2026)
- `index.html`: title, description, canonical, robots, author, Open Graph and Twitter tags, and JSON-LD (WebSite, VideoGame, and Person "Shalom Uwagboe" as creator, author and owner).
- `public/about/index.html`: "About Benin Life" with the creator and owner stated in plain words (AboutPage + Person JSON-LD).
- `public/faq/index.html`: FAQ including "Who is the owner of Benin Life?" (FAQPage JSON-LD, which can show as a direct answer on Google).
- `public/robots.txt` (blocks /admin and /auth, points to the sitemap) and `public/sitemap.xml` (home, about, faq, terms, privacy).
- Static files are served by Vercel before the SPA rewrite, so /about/ and /faq/ are real crawlable pages.

## Owner to-dos (these decide how fast it works; the code alone cannot)
1. **Google Search Console**: add playbeninlife.app (DNS or HTML tag verification), submit https://playbeninlife.app/sitemap.xml, then "Request indexing" for `/`, `/about/`, `/faq/`.
2. **Bing Webmaster Tools**: same (import from Search Console is one click).
3. **Link to the site from everywhere you own**: TikTok bio, Instagram bio, X bio, WhatsApp channel, every post caption. Use the exact name "Benin Life" and "Shalom Uwagboe" in the bio text.
4. **Get other sites to mention it**: a Nairaland post, local Benin blogs, student groups, a Product Hunt or similar listing, any press. Links from other sites matter most for ranking.
5. Keep the name consistent: "Benin Life by Shalom Uwagboe" on TikTok, Instagram, X and LinkedIn.
6. Add the Instagram and X links to `sameAs` in `index.html` once they exist.

Results take days to weeks. Ranking first for the generic words "Benin Life" depends on links and activity; the owner question is the easiest win because of the FAQ and About pages.

## If another site or game uses the name "Benin Life" (28 Oct 2026)
We cannot remove another site from Google. What we do: make ours the clearly official one (title says "Official Site", About and FAQ say it is the official game, structured data names Shalom Uwagboe as creator and owner), get it indexed (Search Console), and link to it from every profile we own.
Evidence the game is ours: the first commit of this repository is 4 Oct 2026, the git history is a dated record of every change, and the TikTok account @beninlife_official_ has dated posts. Keep screenshots (with dates) of the other page.
If they copied our name, text, art or design: report it to their host (for a Playdrop-hosted page, the platform's abuse or copyright contact) and, for copying of text, art or code, use Google's copyright removal form. A name alone is a trademark matter: registering "Benin Life" with the Trademarks Registry and talking to a lawyer are the real fixes.
