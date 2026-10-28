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
