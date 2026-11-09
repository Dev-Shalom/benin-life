# Sponsor outreach

How the automated sponsor emails work, and how new businesses are found.

## Sending (Make scenario 10128539)

- Sends from **shalom@playbeninlife.app** (Cloudflare Email Routing receives, Brevo SMTP sends, Gmail "Send mail as" on code.devshalom@gmail.com).
- Weekdays, hourly from 9am to 1pm Lagos time: **1 email per run, 4 a day**. Free Make plan = 1,000 operations a month; this pace with follow-ups fits.
- Every email (first and follow-up) is Bcc'd to Shalom's personal Gmail as the confirmation copy.
- Reads the tracker sheet `1AFVISc-oj-ziiTCd3OKXM1eViuqJ8hlzZ5fMgp7GUC4` (sheet "Untitled"). Only rows with Status **Pending** and an email in column D are sent. After sending: Status = Sent, column I = date.
- The 9am run also checks rows sent 5+ days ago with an empty column K: a reply (or bounce) marks them Replied; otherwise one follow-up is sent and the row becomes Followed up.
- Column K filled = never followed up (the 12 rows that got the broken 9 Nov email say "Not following up").

## The email

Plain text, no price, no link except the website in the signature. Subject: `{Business} in Benin Life`. The paragraph from column L (the personal line) is the category offer below. A business only ever gets the offer for its own category.

## Category offers (column L)

`{b}` is the business name. Offers describe what we would build if they partner with us; we build it once they invest.

| Category | Covers | Offer |
|---|---|---|
| Restaurant | restaurants, local food spots, shawarma and grills, pizza places | For {b}, we would build your restaurant into the streets of the game, with your name on the front, your real dishes on the menu and a billboard nearby, so players see you every time they get hungry in the city. When they head out in Benin for real, yours is the place they already know. |
| Catering & small chops | caterers, small chops, party food | Players host parties, birthdays and gatherings in the game every week. {b} would be the caterer behind them, with your name on the food at every event and a billboard on the streets, so young people planning real events in Benin already know who to call. |
| Bakery & cakes | bakeries, cake makers | Birthdays and celebrations happen in the game every day. {b} would be the bakery players visit for their cakes, with your shop on the streets and your name on every celebration, so real orders come to you. |
| Cafe & drinks | cafes, juice and smoothie bars, ice cream spots | {b} would be a real spot on the streets of the game where players stop to relax and meet friends, with your name and drinks inside the game and a billboard nearby, so it becomes their go-to place in real life too. |
| Food delivery | food delivery and cloud kitchens | {b} would be the delivery service of the city in the game, with your branded riders moving through the streets and your real offers shown to players, so when they order food in Benin, they order from you. |
| Lounge, bar & club | lounges, bars, clubs, rooftop spots | Nightlife is one of the busiest parts of the game. {b} would be built into the city as a venue players walk into on a night out, with your name on the street outside and your real events and offers announced to every player, so they come through your doors in person too. |
| Event centre | event halls and venues | Players host parties and events in the game every week. {b} would be the venue behind them, with your name at the entrance and your real bookings and open dates promoted in the game, so young people planning real celebrations in Benin think of you first. |
| Event planner & services | event planners, DJs, MCs, decorators, photographers, videographers, party rentals | Players throw parties and events in the game every week. {b} would be featured as the name behind them, with a billboard on the streets and your real services promoted to every player, so the next time they plan an event in Benin, they call you. |
| Shows & concerts | concert, comedy and show promoters | We would promote your real shows inside the game, with billboards on the streets, announcements to every player and a branded event in the city, so young people in Benin hear about {b} where they already spend their time. |
| Gym & fitness | gyms, fitness trainers, dance studios | {b} would have its own gym on the streets of the game where players walk in to train, with your name on the building and your real membership offers announced to players, so young people in Benin who want to get fit already know where to go. |
| Sports academy | football and sports academies | {b} would have its own pitch and training ground in the game, with your name on the gates and your real trials and sessions announced to players, so young people in Benin who love the game find you first. |
| Barber & salon | barbershops, hair salons, nail and lash studios, spas, makeup artists | Looking good matters a great deal to our players. {b} would have its own studio on the streets of the game where players go to change their look, with your name on the front and your real offers shown to players, so they book you in real life. |
| Beauty & skincare | skincare, perfume and cosmetics shops | {b} would be a shop on the streets of the game where players buy their beauty and grooming products, with your products on the shelves and your real offers shown to players, so they come to you for the real thing. |
| Fashion & boutique | boutiques, thrift sellers, sneaker stores, tailors and designers | Style matters a great deal to our players. {b} would have its own boutique on the streets of the game, with your real outfits for players to wear and your name on every piece, so they come looking for you in person. |
| Phones & gadgets | phone and gadget shops, phone repair, accessories | Every player in the game carries a phone. {b} would be the shop on the streets where they buy and fix them, with your name on the front and your real deals shown to players, so they come to you when they need the real thing. |
| Supermarket & mall | supermarkets, mini marts, malls | Shopping is part of everyday life in the game. {b} would be a store on the streets where players buy their daily items, with your name on the front and your real offers shown to players, so they shop with you in real life too. |
| Tutorial & skills centre | JAMB/WAEC/IELTS tutorial centres, coding and tech schools, skills academies | Many of our players are students and young people building their future. {b} would be a centre on the streets of the game where players go to learn, with your name on the building and your real classes and admissions announced to players. |
| University | universities and polytechnics | Many of our players are students or about to be. {b} would have its own campus in the game that players can visit, with a launch event for your students and your admissions announced to every player. |
| Hostel & student housing | hostels near campuses, student housing | Many of our players are students looking for a place to stay. {b} would be a place players can live in the game, with your name on the building and your real rooms shown to players, so students searching for accommodation in Benin find you first. |
| Real estate | estate agents, property firms | Renting and owning a home is part of everyday life in the game. {b} would be the agency players use to find their homes, with your real listings shown in the game and your name on the properties, so young people looking for a place in Benin come to you. |
| Short-let & apartments | short-let apartments | {b} would be featured as the place players book when they want somewhere special to stay in the city, with your real apartments shown in the game and your name on the building, so real bookings come to you. |
| Furniture & interiors | furniture stores, interior designers | Players furnish their homes in the game. {b} would be the store they buy from, with your real pieces in the game and your name on every item, so they come to you when furnishing a real home. |
| Cars & driving | car rentals, driving schools, car wash and detailing, mechanics | Driving is one of the most popular parts of the game, on Sapele Road and across the city. {b} would be built into the streets as the place players go for their cars, with your name on the building and your real offers shown to every driver. |
| Logistics & dispatch | dispatch riders, logistics companies | Players move around the city in the game every day. {b} would be featured as the delivery service of the city, with your branded bikes and vans on the streets and your real services promoted to players. |
| Everyday services | laundry and dry cleaning, printing and branding shops | {b} would be built into the streets of the game as a service players use in their daily life, with your name on the front and your real offers shown to players, so they come to you in person. |
| Money & POS | POS businesses, small savings and loan businesses | Players earn, save and spend money in the game every day. {b} would be featured as a trusted place to handle money in the city, with your name on the streets and your real services shown to players. |
| Internet & power | internet providers, data resellers, solar and inverter installers | {b} would help power the city in the game, with your name on billboards across the streets and your real offers shown to players, so young people in Benin think of you first when they need it. |
| Digital & web agency | web designers, digital marketing agencies | Many of our players are young people starting their own businesses in the game. {b} would be featured as the agency that helps them grow, with a billboard on the streets and your real services promoted to players. |
| Health & pharmacy | pharmacies, dental and eye clinics, private hospitals, labs | {b} would be built into the city as the place players go for care, with your name on the building and your real services shown to players, so young people in Benin know where to go when they need it. |
| Cinema & recreation | cinemas, game centres, recreation parks | Going out for fun is a big part of the game. {b} would be built into the city as a place players visit, with your name on the front and your real shows and offers announced to players, so they come to you for real. |
| Music & entertainment | music studios, artists, record labels | Music plays all over the city in the game. We would feature {b} inside the game, with billboards on the streets and announcements to every player, so young people in Benin hear about you where they spend their time. |
| Hotel | hotels | When players spend time in the city, they need a place to stay. {b} would be built into the game as a hotel players can walk into, with your name outside and your real offers shown to players, so yours is a name young people already know. |
| Media | radio, TV and online media | I would welcome a media partnership, with {b} featured on billboards and at events inside the game, and your shows and stories announced to players. |
| Large Edo company | large Edo-based companies (title partner) | As a proud Edo company, {b} would be featured across the city in the game as a title partner, in front of young Edo people every day, in a game set in their own city. |

## Daily new leads

A scheduled task runs every morning (06:37 Lagos). It finds about 4 real Benin City businesses from the categories above that are not already in the tracker or in earlier lead files, and saves them as a new Google Sheet named `New leads YYYY-MM-DD` in the Drive folder **Benin Life - New leads (daily)** (`1OMOVqMmWmbLgfq3_Go0VWmjrvAB_tYlT`).

The columns match the tracker exactly (A to N): `#, Category, Business, Email, Priority, Status, Subject, Message, Date sent, Reply, Follow-up date, Personal line, Source, Notes`. Status is `Pending`, Subject/Message/Date sent/Reply/Follow-up date are empty, Personal line is the category offer with the name filled in, Source is the page where the email was found.

**To approve:** open the day's file, delete any row you don't want, copy the rest (from column A, without the header) and paste it below the last row of the tracker. From the next run they are sent.

Rules for the finder:
- Real businesses in Benin City only, with an email found on a public page (own website, Instagram/Facebook bio, Google Business, finelib, etc.). Put that page in Source. No guessed emails.
- Prefer small and growing businesses aimed at young people. Spread across categories; rotate so every category gets covered over time.
- Never add a business already in the tracker or an earlier lead file (match by name and by email).
- Use the exact offer for the business's category. Never mention another category's features.
- No real politicians or parties. No em dashes.
