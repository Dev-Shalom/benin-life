// The Help app's articles, as data (docs/ONBOARDING.md).
//
// RULE: when you add a feature, add a Help article here AND a tour step in tourSteps.ts.
//
// Facts come from docs/*.md and the code. Never write a price that an admin can change: say "check the app for current
// prices". Copy is English with light Pidgin, short sentences.
//   id       URL-safe slug. Deep link: /play?go=help:<id>
//   topic    one of HELP_TOPICS (the order below is the order in the app)
//   steps    "How to" list, in order
//   where    where to find it in the game
//   tips     optional extra lines
//   tour     step ids from tourSteps.ts for the "Show me" button (omit when no step fits)
//   keywords extra search words (slang, old names)

export const HELP_TOPICS = [
  { id: 'start', label: 'Getting started', icon: '🚀' },
  { id: 'needs', label: 'Needs', icon: '🍲' },
  { id: 'money', label: 'Money', icon: '💰' },
  { id: 'travel', label: 'Travel & Map', icon: '🗺️' },
  { id: 'home', label: 'Home & furniture', icon: '🏠' },
  { id: 'buying', label: 'Buying', icon: '🛒' },
  { id: 'jobs', label: 'Jobs & careers', icon: '💼' },
  { id: 'hustles', label: 'Hustles', icon: '💪' },
  { id: 'skills', label: 'Skills', icon: '⭐' },
  { id: 'school', label: 'School', icon: '🎓' },
  { id: 'challenges', label: 'Challenges', icon: '🏆' },
  { id: 'clubs', label: 'Clubs, spray & hype', icon: '🪩' },
  { id: 'lounge', label: 'The Lounge', icon: '🥂' },
  { id: 'friends', label: 'Benin Gist, friends & messages', icon: '🗣️' },
  { id: 'family', label: 'Family & love', icon: '💞' },
  { id: 'stories', label: 'Daily stories', icon: '📖' },
  { id: 'notifications', label: 'Notifications', icon: '🔔' },
  { id: 'invest', label: 'Invest & save', icon: '📈' },
  { id: 'yahoo', label: 'Yahoo & EFCC', icon: '💻' },
  { id: 'babalawo', label: 'Babalawo', icon: '🪔' },
  { id: 'billboards', label: 'Billboards', icon: '📺' },
  { id: 'crime', label: 'Crime & jail', icon: '🚓' },
  { id: 'politics', label: 'Politics & elections', icon: '🗳️' },
  { id: 'music', label: 'Music', icon: '🎵' },
  { id: 'safety', label: 'Safety & reporting', icon: '🛡️' },
  { id: 'contact', label: 'Contact', icon: '✉️' },
] as const;

export type HelpTopicId = (typeof HELP_TOPICS)[number]['id'];

export interface HelpArticle {
  id: string;
  topic: HelpTopicId;
  title: string;
  summary: string;
  steps?: string[];
  where?: string;
  tips?: string[];
  tour?: string[];
  keywords?: string;
}

export const HELP_ARTICLES: HelpArticle[] = [
  // ---- Getting started -------------------------------------------------------------------------------------------
  {
    id: 'welcome',
    topic: 'start',
    title: 'How Benin Life works',
    summary: 'You play a Sim living in Benin City. Look after your needs, earn money, make friends and build the life you want.',
    steps: [
      'Check your needs bars (bottom left). Keep them green.',
      'Tap a place on the Map, or "Things to do" at home, and pick an activity card.',
      'Earn money from jobs, hustles and challenges, then spend it on food, furniture, cars and fun.',
      'Meet other players in places, in the chat and in Messages.',
    ],
    where: 'The bottom bar has Home, Buy, Map and Phone. The top bar shows the time, your mood and your cash.',
    tips: ['Stuck? Search this Help app, or tap Show me on any article.'],
    tour: ['welcome', 'needs', 'place'],
    keywords: 'start begin new player tutorial basics',
  },
  {
    id: 'about',
    topic: 'start',
    title: 'About Benin Life',
    summary: 'Benin Life is a free life-sim set in Benin City, Edo State. It was inspired by Lagos Life, and brings that same city-life fun home to Benin City.',
    steps: [
      'Walk, ride and Bolt around real Benin places: Oba Market, Ring Road, Ramat Park, UNIBEN, Ugbowo, GRA, Sapele Road, the Ikpoba River and more.',
      'Work, hustle, study, invest and party. Chat and make friends with real players.',
      'Everything is in English with a little Pidgin. It is for players 18 and over.',
    ],
    where: 'Settings (Sim sheet, then Settings) has the legal pages. Contact us from the Feedback app.',
    tips: ['Benin Life is in beta. New things land often, so check What’s new in this app.'],
    keywords: 'lagos life inspired benin city edo about who made',
  },

  // ---- Needs -----------------------------------------------------------------------------------------------------
  {
    id: 'needs',
    topic: 'needs',
    title: 'Your needs and how to fix them',
    summary: 'Six bars show how your Sim feels: hunger, energy, fun, social, hygiene and toilet. Low bars make life harder, so top them up.',
    steps: [
      'Hunger: eat in your home kitchen, use food from your Bag, or order on the Chowdeck app.',
      'Energy: sleep in your bed at home.',
      'Toilet: use the bathroom at home, or the restroom at a place.',
      'Hygiene: take a bath at home.',
      'Fun and Social: watch TV, play games, hang out with people, or go out.',
    ],
    where: 'The needs card is bottom left. Tap it to open your Sim sheet. A red chip in the Today pill tells you what to fix first.',
    tips: ['At home, tap the furniture (bed, kitchen, bath, toilet, TV) to do the activity.'],
    tour: ['needs'],
    keywords: 'hunger energy sleep toilet bladder hygiene fun mood eat food tired',
  },

  // ---- Money -----------------------------------------------------------------------------------------------------
  {
    id: 'cash-bank',
    topic: 'money',
    title: 'Cash and bank',
    summary: 'You have two kinds of money. Cash is in your pocket and can be stolen on the street. Bank money is safe.',
    steps: [
      'Check both at the top right (cash) and in the Bank app (bank balance).',
      'Put cash in the bank at Bronze Bank (banking hours) or at any PoS stand (a small charge applies).',
      'Take money out the same way when you need cash.',
    ],
    where: 'Phone, then Bank. Bronze Bank and the PoS stands are on the Map.',
    tips: ['At night, carrying a lot of cash is risky. The Today pill will remind you to bank it.'],
    tour: ['money', 'bank'],
    keywords: 'naira wallet balance deposit withdraw pos atm',
  },
  {
    id: 'topup',
    topic: 'money',
    title: 'Top up with Paystack',
    summary: 'You can buy game naira with a real payment through Paystack. It is secure: Benin Life never sees your card details.',
    steps: [
      'Tap the green + next to your cash at the top right.',
      'Choose a pack. Check the app for current packs and prices.',
      'Pay in the Paystack window. The money lands in your bank balance when the payment is confirmed.',
    ],
    where: 'The + next to your cash opens your Wallet.',
    tips: [
      'If the Wallet says "Coming soon", top-ups are switched off for now.',
      'Paid but nothing arrived? Send us a Feedback with your payment reference.',
    ],
    tour: ['money'],
    keywords: 'paystack buy naira payment card wallet plus pay real money',
  },
  {
    id: 'transfers',
    topic: 'money',
    title: 'Send money to a friend',
    summary: 'Send bank money to another player. The fee grows with the amount and you see it before you confirm. There are daily limits and a waiting rule for new accounts.',
    steps: [
      'Open Phone, then Bank, then the Send tab.',
      'Type their username, the amount and an optional note.',
      'Check the fee on the confirm card (it shows the fee and any stamp duty), then tap Send.',
    ],
    where: 'Phone, then Bank, then Send.',
    tips: [
      'The waiting rule: a brand-new account must wait before it can send money. This stops cheats. Check the app for the exact wait.',
      'Big transfers pay a higher fee, and once you have sent a lot in one day the fee doubles until tomorrow. Tips pay the same fee.',
      'There is also a short wait between transfers and a limit on how much you can send each day.',
      'Transfers come out of your bank balance, never your cash.',
    ],
    tour: ['bank'],
    keywords: 'transfer send money gift friend fee limit wait new account stamp duty',
  },
  {
    id: 'taxes-bills',
    topic: 'money',
    title: 'Taxes & bills',
    summary: 'Earn big and you share a little with Edo State. Own things and they send bills. Everything is shown before it is charged, and new players get a grace period.',
    steps: [
      'Income tax: every Monday the state looks at what you earned that week from jobs, hustles, business and interest. The first part is free, and only the big weeks pay more. See Phone, Bank, Bills.',
      'Bills: every Monday your house, cars, businesses and land send a bill with a due date. They are paid for you on the due date when the money is in your bank or pocket, or you can pay them early.',
      'Late? A small late fee is added. Only after a long time unpaid does a car stop driving or a business stop earning, until you pay. Nothing is ever taken from you.',
      'Shop prices include VAT, and luxury things (cars, big laptops, status items) add a luxury levy. Food and basic needs have none. The price you see is the price you pay.',
      'Sending money has a fee that grows with the amount, plus a small stamp duty on bigger transfers. You see it before you confirm.',
    ],
    where: 'Phone, then Bank, then Bills. The tax rates are also shown in Benin Votes.',
    tips: [
      'New players pay no tax and get no bills for the first days. Check the app for how long.',
      'Cannot pay your tax in full? What you cannot pay becomes "tax owed", and your next earnings pay it first. You never go below zero.',
      'The Governor can declare a Tax holiday that cuts the rates for the whole term.',
      'Rich and want to be seen? In Bank, Status you can donate to the city, throw a city party or buy a Chief title.',
      'Check the app for current rates: they can change.',
    ],
    tour: ['bank'],
    keywords: 'tax income bills vat levy stamp duty irs revenue house light nepa insurance council ground rent late fee owed donate party chief title philanthropist',
  },

  // ---- Travel & Map ----------------------------------------------------------------------------------------------
  {
    id: 'map',
    topic: 'travel',
    title: 'Travel and the Map',
    summary: 'The Map shows every place in Benin City. Tap one, then choose how to get there.',
    steps: [
      'Tap Map in the bottom bar.',
      'Tap a place. Its card opens.',
      'Tap Go there and pick a way: walk, keke, bus, drop, Bolt or your own car.',
      'Check the price, time and risk on each option, then tap to book.',
    ],
    where: 'Map is in the bottom bar. You can also tap Join them on a friend in Messages.',
    tips: [
      'Walking is free but slow. Some night trips are risky, so check the risk label.',
      'You can also book a ride in the Bolt app on your phone.',
    ],
    tour: ['map'],
    keywords: 'walk keke bolt bus drop car ride travel go place map',
  },
  {
    id: 'hours',
    topic: 'travel',
    title: 'Open and closed places',
    summary: 'Most places have opening hours. If a place is closed, its card says when it opens.',
    steps: [
      'Tap the place on the Map to see "Open now" or "Closed now, opens at...".',
      'Plan your trip so you arrive when it is open.',
    ],
    where: 'On the place card and on the Map pins.',
    tips: [
      'Clubs open at night, around 9 or 10 PM until 5 AM.',
      'The bank has banking hours, but PoS stands work any time.',
      'Some clubs are switched off for a while. They show "Closed for now".',
    ],
    tour: ['map'],
    keywords: 'hours open closed opening time schedule',
  },

  // ---- Home & furniture ------------------------------------------------------------------------------------------
  {
    id: 'home',
    topic: 'home',
    title: 'Going home and resting',
    summary: 'Home is your base. Sleep, cook, bath and relax here.',
    steps: [
      'Tap Home in the bottom bar to go back any time.',
      'Tap the bed to sleep and recover energy.',
      'Tap the kitchen to cook, the bath to wash, the TV for fun.',
    ],
    where: 'Home is in the bottom bar. Tap "Things to do" for the full list.',
    tips: ['You can invite friends home from Messages. You let them in.'],
    tour: ['home'],
    keywords: 'sleep bed cook kitchen rest house flat',
  },
  {
    id: 'arrange',
    topic: 'home',
    title: 'Arrange your furniture',
    summary: 'Move, turn and store your furniture to make the room yours.',
    steps: [
      'Tap Buy, then the Arrange tab.',
      'Tap a piece, then drag it where you want it.',
      'Tap Done to save. You can also store a piece in your Bag.',
    ],
    where: 'Buy, then Arrange (you must be at home).',
    tour: ['buy'],
    keywords: 'furniture arrange move rotate decorate room layout',
  },
  {
    id: 'house-upgrades',
    topic: 'home',
    title: 'Upgrade your home',
    summary: 'Expand or improve the home you live in, instead of moving.',
    steps: [
      'Open Phone, then Houses, and scroll to Upgrade your home.',
      'Tap an upgrade to see what it costs, how long it takes and what you will get.',
      'Tap Start building. The builders work for real minutes and a scaffold shows on your house.',
      'You get a message when they finish. New rooms are free floor: use Buy and Arrange to furnish them.',
    ],
    where: 'Phone, then Houses. A builders pill on your home screen shows the progress.',
    tips: [
      'You can add rooms, a garage or an extra car space, power, a borehole, a compound wall and gate, and a better finish.',
      'The big one turns your home into the next size at the same address. Your furniture and garage stay.',
      'The landlord must agree, so each job has a consent fee. If you ever move, you get part of the upgrade money back.',
      'Hostel rooms belong to UNIBEN and cannot be upgraded. Prices and times can change: check the app.',
    ],
    tour: ['houses'],
    keywords: 'upgrade extension extra room bedroom garage generator solar borehole fence gate paint tiles boys quarters builders renovate expand',
  },

  // ---- Buying ----------------------------------------------------------------------------------------------------
  {
    id: 'buy',
    topic: 'buying',
    title: 'Furniture, food and your Bag',
    summary: 'The Buy button opens the furniture shop, your Arrange tool and your Bag.',
    steps: [
      'Tap Buy in the bottom bar.',
      'Pick a room tab, and a budget (LAPO, Mid or Nepo).',
      'Tap an item to buy it. You can place it straight away.',
    ],
    where: 'Buy is in the bottom bar. Food in your Bag can be used from there.',
    tips: ['Prices change. Check the app for current prices.'],
    tour: ['buy'],
    keywords: 'shop store furniture bag inventory items',
  },
  {
    id: 'cars',
    topic: 'buying',
    title: 'Cars, clothes and houses',
    summary: 'Cars, the Boutique and Houses each have their own app on your phone.',
    steps: [
      'Cars: open Phone, then Cars. Buy a tokunbo or a brand-new ride. A car also unlocks Bolt driving.',
      'Clothes: open Phone, then Boutique, to buy outfits and change your look.',
      'Houses: open Phone, then Houses, to rent a bigger place. Pay your rent on time.',
    ],
    where: 'Phone: Cars, Boutique, Houses.',
    tips: ['Prices can change. Check the app for current prices.'],
    tour: ['phone'],
    keywords: 'car vehicle clothes boutique outfit house rent move flat duplex',
  },

  {
    id: 'company',
    topic: 'money',
    title: 'Business: companies, plots and real listings',
    summary: 'One Business app, four tabs: My companies, Map plots, Discover and Real business. Open an online company with no plot, own a shop on the map, browse rankings, or list your real business.',
    steps: [
      'Open Phone, then Business. The four tabs are My companies (online companies, no plot needed), Map plots (shops, bukas and bars on a plot), Discover (every company and Rankings) and Real business (your real shop on the map). On My companies tap Register. Pick a name, an industry, a head office area, a logo and a colour. You pay a registration fee and the setup cost.',
      'Hire staff (they cost a weekly wage and let you serve more customers). Add a Manager, a generator for NEPA, more branches in other areas, and upgrade a Kiosk to a Shop or a Store.',
      'Set your pricing: Cheap brings more people, Premium earns more from each one but can cost you stars. Buy marketing (flyers, radio, influencer) for a boost for a few evenings.',
      'Every evening at 6 PM Benin time your sales settle into the Till. Open the app and tap Cash out to move it to your bank. The till holds only a few evenings, so do not stay away too long.',
      'Check the news for reviews, outages and supplier problems. Sell the company to the system, or put it on the Market for another player.',
      'The Discover tab lists every company and every verified real business. Its Rankings switch shows the top companies by sales this week. Share your company link with friends.',
      'Own a real business in Benin? Open the Real business tab, tap List my real business, add up to three photos, your contacts and a map spot, accept the terms and pay with Paystack (₦25,000 for 30 days, the price can change). The team checks it first. If it is not approved you are refunded automatically.',
    ],
    where: 'Phone, then Business. Tabs: My companies, Map plots, Discover, Real business.',
    tips: [
      'Cash out money counts as earned income, so the weekly tax applies.',
      'Real business listings are adverts only. Only legal businesses: no adult content, gambling, crypto schemes, weapons or drugs.',
      'Prices, fees, caps and chances can change. Check the app for the current numbers.',
    ],
    tour: ['business'],
    keywords: 'company companies startup online business register industry branch kiosk shop store staff manager generator pricing marketing till cash out rating discover rankings real business map listing advert paystack verified',
  },
  {
    id: 'business',
    topic: 'money',
    title: 'Own a business',
    summary: 'Buy a shop, buka, bar or even a filling station. It earns while you hustle, and you grow it with upgrades and staff.',
    steps: [
      'Open Phone, then Business, then the Map plots tab, then Buy a business. Pick a kind, then a free plot (Ring Road, Uselu, Ugbowo, Sapele Rd, Airport Rd, GRA ...). Plots are limited: first come, first served.',
      'Give it a name. Everybody sees it on the map as "Name · @you". The builders need a few minutes, then the money starts.',
      'Come back and tap Collect takings. Takings stop growing after about two days, so log in often.',
      'Restock shops, bukas and bars to keep income at 100%. With empty shelves income slides down.',
      'Hire staff for more income, or go to your place and Work a shift: a boost and Business XP. Upgrade for a higher level and more income.',
      'Other players who spend at your place pay you a share. Sell the business back to the system, or to another player on the Market.',
    ],
    where: 'Phone, then Business, Map plots tab. Your places also show on the map, and the place card has Collect and Work a shift.',
    tips: [
      'Bigger businesses need the Business skill, or a certificate from School (a filling station needs Business Management). The buy list tells you what is missing.',
      'Bad days happen: robbery (insurance helps), NEPA outage, a council levy, staff theft. Good days happen too.',
      'Prices, income, caps and chances can change. Check the app for the current numbers.',
    ],
    tour: ['business'],
    keywords: 'business shop buka bar bukateria filling station salon pos car wash event centre chemist plot own takings collect restock staff upgrade passive income',
  },
  {
    id: 'crew',
    topic: 'money',
    title: 'Gangs: team up for group jobs',
    summary: 'Start a gang, recruit players, pool money in the gang bank and run group jobs for big loot. It is a game: the police can catch everybody.',
    steps: [
      'Open Phone, then Gang. Start a gang: pick a name, a 3 or 4 letter tag, a colour and an emblem. Starting a gang costs a fee, so check the app for the price.',
      'Invite friends first, or anybody by username. New recruits start as Prospects; the Boss and Lieutenants promote them. Rejoining another gang after leaving has a cooldown.',
      'Members put money in the gang bank. The Boss and Lieutenants spend it on gang upgrades, and every deposit and spend is logged.',
      'Open a job from the Jobs tab. Members who are online and standing at a meeting spot join the lobby. When the countdown ends (or the leader starts it) the job runs and rolls once.',
      'Paid: the loot splits between the gang bank and the members, by the share the Boss sets. Caught: the whole gang goes to the police cell, with bail, serve time or escape like any arrest.',
      'Paid jobs give the gang XP. Higher gang levels unlock more members, better jobs and a loot bonus. The Ranks app has a weekly Top gangs board.',
    ],
    where: 'Phone, then Gang. Your gang tag also shows next to your name in places, chat and profiles.',
    tips: [
      'Skills like Charisma, Fitness and Driving lower the chance of being caught.',
      'A gang can only run a few jobs a day, and a disbanded gang keeps a small fee from its bank.',
      'Gang jobs never take money from other players.',
      'Chances, prices, cooldowns and prizes can change. Check the app for the current numbers.',
    ],
    tour: ['crew'],
    keywords: 'gang crew group job heist boss lieutenant member prospect tag emblem bank invite recruit loot police jail top gangs crews',
  },
  {
    id: 'cooking',
    topic: 'buying',
    title: 'Cooking and market prices',
    summary: 'Buy ingredients, cook at home on your stove, and eat, share or feed the kids. Open Phone, then Chowdeck: the Kitchen and Prices tabs.',
    steps: [
      'Buy ingredients (rice, beans, yam, palm oil, pepper, crayfish and more) in small portions: a cup, a derica, a tuber, a bunch, a sachet. Go to Oba Market or Edo Fresh Supermarket and open the Shop tab.',
      'Oba Market is cheaper but only open in the day, and its prices move a little every Benin day. The supermarket is dearer, always open and its prices never change. The Prices tab in Chowdeck shows today\'s prices and whether each one is up or down since yesterday.',
      'Go home, then open Phone, Chowdeck, Kitchen (or tap your cooker and choose Open the kitchen). Pick a pot size and tap Cook on a dish. The server checks and takes the ingredients and puts the portions in your Bag.',
      'Eat a portion from the Bag (or Eat one right after cooking) to fill Hunger and get a little Energy and Mood.',
      'With a partner, tap Send to give them portions. Feeding a child from Nursery up? A cooked portion in your Bag is used instead of lunch money, and fills them up more.',
    ],
    where: 'Phone, then Chowdeck: Food, Drinks, Kitchen, Prices. Ingredients: the Shop tab at Oba Market and Edo Fresh Supermarket.',
    tips: [
      'You need to be at your own home with a stove or cooker.',
      'Cooking raises your Cooking skill. Harder dishes need a higher level, and Black soup needs the Catering certificate from the School app. Catering also cooks faster.',
      'Cooking XP has a daily limit, and easy dishes give less, so the best way to level is to try new dishes.',
      'Cooked food cannot be sold. Ingredients cannot be sold back. Check the app for current prices and limits.',
    ],
    tour: ['cooking'],
    keywords: 'cook cooking kitchen recipe ingredients food rice beans yam soup jollof egusi owo banga black soup stove oba market supermarket edo fresh prices groceries catering share kids feed',
  },
  {
    id: 'market',
    topic: 'buying',
    title: 'Benin Market: buy and sell with players',
    summary: 'Sell your cars, land, furniture and gadgets to other players, or buy from them, from the Market app on your phone.',
    steps: [
      'To sell, open the thing: Bag for items, Phone then Cars for a car, Buy then Arrange for furniture, or Bank then Invest for land. Tap Sell to players.',
      'Set a price. The sheet shows the lowest and highest price allowed and what you get after the market fee. Tick Open to offers if you want lower bids, or type a friend\'s username to sell only to them.',
      'Your thing is locked while it is listed: you cannot use it, place it or drive it. Take it down any time, or it comes back by itself when the listing ends.',
      'To buy, open Phone then Market. Filter by Items, Furniture, Cars or Land, search, and sort by price or best deal. Tap a card, check the seller and the condition, then confirm.',
      'Offers: on a listing marked Offers, tap Make an offer. The seller gets an alert and can accept or decline. If they accept and you still have the money, you buy it at your offer.',
    ],
    where: 'Phone, then Market. Browse, My listings (cancel, answer offers) and My offers (withdraw).',
    tips: [
      'A market fee comes off every sale. Check the app for the current fee and price limits.',
      'Cars keep their plate and wear. Plots keep their cost, and any pending land deal must be finished before you sell plots.',
      'Furniture that is placed must be picked up first (Store). Pieces that came with your house, food, drinks and similar things cannot be sold to players.',
      'New accounts must play a while before they can sell to players. Buying is open straight away.',
      'See a scam or something wrong? Open the listing and tap Report this listing.',
    ],
    keywords: 'market marketplace jiji sell buy trade player listing offer car land plot furniture sell to players fee escrow',
  },

  // ---- Jobs ------------------------------------------------------------------------------------------------------
  {
    id: 'jobs',
    topic: 'jobs',
    title: 'Jobs and careers',
    summary: 'Pick a career and climb the ladder: tech, PoS and fintech, trade, transport, health and education.',
    steps: [
      'Open Phone, then Jobs, and tap Apply on a job.',
      'Go to work and start a shift. You are paid when it ends.',
      'Do good shifts to get promoted. The Career tab in your Sim sheet shows your progress.',
    ],
    where: 'Phone, then Jobs. Your Sim sheet has a Career tab.',
    tips: [
      'You can only do a few shifts each game day.',
      'Some levels need a certificate or a laptop. The job card tells you.',
    ],
    tour: ['jobs'],
    keywords: 'work shift salary promotion career apply job laptop',
  },

  // ---- Hustles ---------------------------------------------------------------------------------------------------
  {
    id: 'hustles',
    topic: 'hustles',
    title: 'Hustles: side money',
    summary: 'Hustles are quick ways to earn: Bolt driver, PoS agent, food stall, fishing, DJ, MC, tutor, mechanic and more.',
    steps: [
      'Open Phone, then Hustles, or tap a hustle card at the right place.',
      'Check what it needs: a tool, a stall, a car, or a skill level.',
      'Start it. It runs for a short time and cannot be stopped.',
      'Collect your pay. Some hustles can go wrong, so there is a risk.',
    ],
    where: 'Phone, then Hustles. Hustle cards also sit inside places (the market, the motor park, clubs, UNIBEN).',
    tips: ['Each hustle has a wait and a daily limit. Your skills and certificates make it pay more.'],
    tour: ['hustles'],
    keywords: 'hustle bolt pos jollof fishing dj mc tutor mechanic side money earn',
  },

  // ---- Skills ----------------------------------------------------------------------------------------------------
  {
    id: 'skills',
    topic: 'skills',
    title: 'Skills and levels',
    summary: 'Doing things trains skills. A higher level means better pay and opens better work.',
    steps: [
      'Open your Sim (tap the needs card), then the Skills tab.',
      'Tap a skill to see your XP, what the next level gives and where to train it.',
      'Train by working, hustling, taking classes or doing activities.',
    ],
    where: 'Sim sheet, then Skills. A pop-up with confetti shows when you level up.',
    tips: ['Cards show "Needs Mechanic lvl 2" when a skill level is required.'],
    tour: ['skills'],
    keywords: 'skill xp level train yahoo driving cooking music teaching fishing mechanic business fitness charisma',
  },

  // ---- School ----------------------------------------------------------------------------------------------------
  {
    id: 'school',
    topic: 'school',
    title: 'School and certificates',
    summary: 'Study to earn certificates. They unlock better jobs and give a lasting pay boost.',
    steps: [
      'Open Phone, then School.',
      'Pick a course and enrol. Check the app for current fees.',
      'Go to the school place and take a class. You can take one class a day.',
      'Finish all the classes (some end with an exam) to get your certificate.',
    ],
    where: 'Phone, then School. Course cards are also at UNIBEN, the motor park, the Mechanic Village and the Tech Hub.',
    tips: ['Some courses need an earlier certificate or a skill level first.'],
    tour: ['hustles'],
    keywords: 'school class course certificate exam degree uniben ict driving',
  },

  // ---- Challenges ------------------------------------------------------------------------------------------------
  {
    id: 'challenges',
    topic: 'challenges',
    title: 'Daily and weekly challenges',
    summary: 'Three small daily goals and three bigger weekly goals. Finish them for cash and prizes, and open a chest when you finish a set.',
    steps: [
      'Open the Today pill (top left) and tap Challenges.',
      'Do the thing: finish a hustle, visit a place, spray at a club, and so on.',
      'Come back and tap Claim on a finished challenge.',
      'Finish them all to open the chest.',
    ],
    where: 'The Today pill, top left. A red dot means something is ready to collect.',
    tips: ['Daily goals reset at midnight Benin time. You can swap one challenge a day.'],
    tour: ['today'],
    keywords: 'challenge daily weekly goal chest reward claim today',
  },

  // ---- Clubs -----------------------------------------------------------------------------------------------------
  {
    id: 'clubs',
    topic: 'clubs',
    title: 'Clubs, spray and hype',
    summary: 'Clubs come alive at night. Dance, spray money and get a shout-out from the MC.',
    steps: [
      'Travel to a club after dark. Clubs open around 9 or 10 PM and close at 5 AM.',
      'Tap the Dance floor or the DJ booth, then Spray money.',
      'Type any amount you can afford from your cash, or tap a quick chip, then Spray.',
      'The MC shouts your name, and your hype points go up.',
    ],
    where: 'Clubs are on the Map. Look for the club pins that are open.',
    tips: [
      'Spray uses cash, not bank money. Withdraw first at a PoS stand.',
      'Bigger sprays get bigger moments. Weekend nights can cost more.',
    ],
    tour: ['nightlife'],
    keywords: 'club night spray hype mc dj dance vip party amapiano',
  },

  // ---- Lounge ----------------------------------------------------------------------------------------------------
  {
    id: 'lounge',
    topic: 'lounge',
    title: 'The Members’ Lounge',
    summary: 'The Lounge, GRA is a calm, classy place that is open all day. You need a pass to enter.',
    steps: [
      'Open the Lounge from the Map and tap to get a pass. There is a day pass, a monthly pass and a VIP pass.',
      'Order drinks, play pool and network. Networking trains your charisma.',
      'VIP has a private cabana, and you can bring a friend as a guest.',
    ],
    where: 'The Lounge pin in GRA on the Map. Friends can bring you in from Messages.',
    tips: ['Passes run out after a time. Renew from the same place. Check the app for current prices.'],
    tour: ['nightlife'],
    keywords: 'lounge members pass vip day gra pool cabana',
  },

  // ---- Friends & messages ----------------------------------------------------------------------------------------
  {
    id: 'friends',
    topic: 'friends',
    title: 'Friends and messages',
    summary: 'Add friends, send private messages and voice notes, and visit each other. It all lives in Benin Gist.',
    steps: [
      'Open Phone, then Benin Gist, then the Friends tab.',
      'Search "@username" and send a friend request.',
      'Friends who are online show a green dot. Tap Message to chat (Chats tab).',
      'Tap Join them to travel to where they are, or Invite home.',
    ],
    where: 'Phone, then Benin Gist.',
    tips: [
      'You can hide your location from friends with the switch at the bottom of the Friends tab.',
      'Chat where you are: Benin Gist, Groups tab, the first row.',
    ],
    tour: ['phone', 'chat'],
    keywords: 'friend dm message messages chat voice note invite visit house request',
  },
  {
    id: 'benin-gist',
    topic: 'friends',
    title: 'Benin Gist: gists, groups and tips',
    summary: 'Post short gists, like and comment, tip people, chat in group chats and send money to anyone.',
    steps: [
      'Open Phone, then Benin Gist. The Feed tab shows gists: For you (popular and fresh) or Following (friends and people you follow).',
      'Tap "What\'s the gist?" to post. Add a place tag like #RingRoad. A photo is allowed when the owner switches photos on.',
      'Tap the heart to like, the bubble to comment, and Tip to say thanks with money.',
      'Tap a name to see their gists. From there: Follow, Add friend, Message, Send money.',
      'Groups tab: join a public group in Discover, or create your own (public or private). Owners and admins can add friends, mute, remove and pin.',
      'In a group, tap Send money, pick a member and an amount. A gold money bubble shows in the chat.',
    ],
    where: 'Phone, then Benin Gist.',
    tips: [
      'Report anything rude with the three dots. A moderator checks it.',
      'Blocked players never see your gists or messages, and you never see theirs.',
      'Money sent or tipped follows the normal bank rules: fee, daily limit and the new-account wait.',
      'Likes and comments are bundled: "5 people liked your gist".',
    ],
    tour: ['phone'],
    keywords: 'gist feed post like comment tip group groups chat send money discover social instagram twitter whatsapp messages benin gist hashtag',
  },

  // ---- Family & love ---------------------------------------------------------------------------------------------
  {
    id: 'family-love',
    topic: 'family',
    title: 'Family and love',
    summary: 'Ask somebody out, flirt, go on dates together and become a couple.',
    steps: [
      'Open Phone, then Family, then Link-ups. Switch on "Open to link-ups". Only players who are open can see each other.',
      'Tap Ask out beside a player. They get an alert and can say yes or no. A no is private: you only see "No reply".',
      'When they say yes you are "talking". Open the Us tab and send flirts: pick a line from the menu. Lines cost a little money and raise your level together.',
      'When your level reaches the couple mark, you become a couple 💞. It shows in the Family tab and on your profile.',
      'Go out together from the Us tab: pick a date, both be at the place, and both pay your share. Dates give Fun, Social and bond.',
      'Couples can have a baby. In the Family tab, tap Have a baby. Your partner has to say yes, and you each pay a small amount. Then you wait a few days.',
      'When the baby arrives you get an alert. Name them, then look after them together: Feed, Change, Sleep, Play, Medicine and Cuddle. Each stage (Newborn, Baby, Nursery, Primary, Secondary) has its own bars and its own shopping list.',
      'When a bar gets low the child "needs you" and you both get an alert. Open Family and take care of them.',
    ],
    where: 'Phone, then Family.',
    tips: [
      'No free-text flirting: only the preset lines, so nobody can be rude to you.',
      'Ignore each other for a few days and the level slowly drops, so keep the spark alive.',
      'Break up any time from the Us tab. There is a short wait before you can ask again. Use Report if somebody behaves badly.',
      'Prices, waits and the couple level are set by the game admins, so check the app for the current numbers.',
      'Newborns and babies need formula, cereal and diapers from your bag. Buy them at Oba Market (cheaper, the price moves a little each day, open in the day) or the Edo Fresh Supermarket (fixed price, always open). Older children need lunch money in cash, and a toy makes playtime better. Sleep and cuddles are free but have a short wait.',
      'A child can fall ill on any day. Dr. Osagie sends both parents a card: Hospital costs more and almost always works, the Chemist costs less and may not work. Whoever answers first treats the child. You can also treat at home with medicine and a cuddle.',
      'If a bar stays empty for too long the child falls sick (medicine and a cuddle help). If nobody cares for many days, relatives take them in. To bring a child home each parent pays a share (₦200,000 each by default) and the child comes home when both have paid. A very long, ignored illness can end sadly: the Family tab keeps a small candle.',
      'After about three weeks the child grows up and moves out (or goes to university), and you become a Proud parent (Graduate, Gold, Silver or Bronze, with a thank-you gift that grows with what you spent on school). School and university are in the next article. You stay co-parents even if you break up.',
    ],
    tour: ['family'],
    keywords: 'love date dating girlfriend boyfriend couple flirt ask out link up relationship partner kids family marry',
  },
  {
    id: 'family-school',
    topic: 'family',
    title: 'School and university for your child',
    summary: 'Enrol your child, pay the fees, help with homework, read the report cards, and decide about university.',
    steps: [
      'When your child reaches Nursery (day 5), open Family, Kids and tap Find a school. Pick a school that teaches that level. Fees are per class: a dearer school lifts every grade.',
      'School runs fast: about one class a day. Nursery 1 and 2, Primary 1 to 6, then JSS 1 to 3 and SSS 1 to 3. Either parent can pay the fee with the Pay button. If a class fee is not paid before the class ends, your child misses the class and repeats it.',
      'Grades (0 to 100 for each subject) go up with a fed, rested, healthy child, fees paid on time, Homework (once a class for each parent), Textbooks, a School bag and uniform, and Extra lessons. Buy books and uniform at Oba Market or the supermarket, then give them from the School panel.',
      'At the end of each class an average of 50 or more means promoted. Under 50 the child repeats that class. A child who repeats may not reach SSS 3 before growing up.',
      'The school sometimes asks for money: PTA levy, excursion, sports wear, a party, and the WAEC fee. Both parents get the card. The first to pay settles it. Later brings it back; Ignore costs grades and a sad child once both parents ignore it.',
      'After each stage you get a report card with the grades, a position, and the teacher\'s remark. Open Report cards and tap Share to post it or copy it.',
      'At the end of SSS 3 your child sits WAEC. With enough credits including Maths and English, both parents choose on day 21: UNIBEN, Edo Royal University, or work. University takes four levels (100L to 400L), about one a day, with fees each level. Graduating gives a degree class and the top Graduate badge.',
    ],
    where: 'Phone, then Family, then Kids.',
    keywords: 'school class grades report card waec university uniben homework fees kids child graduate degree teacher',
  },

  // ---- Daily stories ---------------------------------------------------------------------------------------------
  {
    id: 'daily-stories',
    topic: 'stories',
    title: 'Daily stories and your path',
    summary: 'One short story a day with a twist. What you choose shapes the way life goes.',
    steps: [
      'Open Phone, then Stories. Every Benin day there is one new story: a few sentences, then two to four things you can do. The Stories icon and a small chip on your screen tell you when it is waiting.',
      'Pick a choice. Some cost a little money, and you pay it up front. Then the outcome is revealed: the colour tells you how it went (green good, red bad, purple a plot twist, gold a laugh), and small chips show what changed.',
      'The twist: the choice is not the whole story. The kind thing sometimes backfires, and the risky thing sometimes pays off. The same choice can end differently on another day.',
      '"Something tells you this isn\'t over…" means a seed was planted. A day or a few days later it comes back as a follow-up story, or as a pop-up moment. Some stories are chapters of a bigger one, and later chapters change with what you chose before.',
      'Read a story every day for a streak. At 3, 7 and 14 days in a row you get a small reward, once for each step. Miss a day and you start again.',
      'Your path so far: the Stories app describes your life in words ("A kind hustler with a bit of luck"). Nobody shows you a score. Now and then you see a quiet line about how people see you.',
    ],
    where: 'Phone, then Stories.',
    tips: [
      'Every choice nudges your hidden path a little: kind or selfish, bold or careful, honest or shady, faithful, family-minded. Over time it changes which stories you get and how they end.',
      'Kind players are sometimes blessed with a small surprise. Players with a lot of trouble sometimes get a visit from the police or EFCC. Luck leans the odds a little. None of it can be farmed for money.',
      'A story only shows what fits your life: no partner story if you are single, no car story if you have no car.',
      'You can get a push when your story is waiting. Turn on Game events in Settings, then Notifications. Check the app for current rewards.',
    ],
    tour: ['stories'],
    keywords: 'story stories daily twist path karma luck streak chapter follow up bitlife choices reputation',
  },

  // ---- Notifications ---------------------------------------------------------------------------------------------
  {
    id: 'notifications',
    topic: 'notifications',
    title: 'Notifications',
    summary: 'Alerts live in the bell on your phone. You can also get phone notifications for messages, money and friends.',
    steps: [
      'Open your Sim, then Settings, and find Notifications.',
      'Turn on Allow notifications and say yes when your browser asks.',
      'Choose which kinds you want: messages, money received, friends, game events, announcements.',
    ],
    where: 'Sim sheet, then Settings. The Alerts app on your phone lists everything.',
    tips: ['On iPhone and iPad, add Benin Life to your Home Screen first. Notifications only work from there.'],
    keywords: 'notification alert push bell ping',
  },

  // ---- Invest ----------------------------------------------------------------------------------------------------
  {
    id: 'invest',
    topic: 'invest',
    title: 'Save and invest',
    summary: 'Put bank money to work. Saving is steady. Investing can earn more, but can also lose.',
    steps: [
      'Put cash in the bank first. Saving and investing use bank money only.',
      'Open Phone, then Bank, then Save or Invest.',
      'Pick a product, choose an amount and confirm. Check the app for current rates.',
      'Come back to collect or sell. Some products lock your money for a time.',
    ],
    where: 'Phone, then Bank, then the Save and Invest tabs.',
    tips: ['Breaking a locked saving early can cost you the interest. Read the card before you commit.'],
    tour: ['bank'],
    keywords: 'invest save savings stocks land farm keke pos treasury bond crypto interest',
  },

  // ---- Yahoo -----------------------------------------------------------------------------------------------------
  {
    id: 'yahoo',
    topic: 'yahoo',
    title: 'Yahoo and EFCC',
    summary: 'Yahoo is a risky in-game hustle. It can pay big, but EFCC can catch you and take everything. It is satire, nothing more.',
    steps: [
      'You need a laptop. Better laptops pay more and lower your risk.',
      'Open Phone, then Yahoo, and pick a job.',
      'Yahoo money goes into a separate balance. You cannot spend it until you cash out.',
      'Cash out to move it to your cash. Every job and cash out has a caught chance.',
    ],
    where: 'Phone, then Yahoo.',
    tips: [
      'If EFCC catches you, part of the Yahoo balance is taken, the laptop may be seized, and you can bail out or go to jail.',
      'Higher Yahoo skill lowers your caught chance. Better jobs need a better laptop and a higher Yahoo level.',
    ],
    tour: ['hustles'],
    keywords: 'yahoo efcc laptop cash out caught bail rank',
  },

  // ---- Babalawo --------------------------------------------------------------------------------------------------
  {
    id: 'babalawo',
    topic: 'babalawo',
    title: 'Baba’s Shrine',
    summary: 'Visit the Babalawo for a reading or a charm. Charms can help your job pay, protect your pocket and more.',
    steps: [
      'Buy the offerings the service needs at Oba Market (kola nut, palm oil and so on).',
      'Travel to Baba’s Shrine on Sakponba Road (open all day).',
      'Pick a service on the Babalawo card and pay with cash and offerings.',
    ],
    where: 'Baba’s Shrine is on the Map. Your active charms show in your Sim sheet.',
    tips: ['Charms last a set time, and sometimes they fail. Check the app for current prices.'],
    keywords: 'babalawo baba shrine charm ifa offering luck protection',
  },

  // ---- Billboards ------------------------------------------------------------------------------------------------
  {
    id: 'billboards',
    topic: 'billboards',
    title: 'Billboards',
    summary: 'Digital billboards stand at busy spots in the city. You can advertise on them.',
    steps: [
      'Open Phone, then Billboards, or tap a board on the Map.',
      'Tap Add your ad on a board. Pick an image, a link and how many days (1, 3 or 7).',
      'Pay securely. The team checks every ad first. Rejected ads are refunded.',
    ],
    where: 'Phone, then Billboards. Boards are also visible on the Map.',
    tips: [
      'Tapping an ad warns you before you leave the game. Never share your password on another site.',
      'See something wrong? Tap Report under the ad.',
    ],
    keywords: 'billboard ad advert advertise board promote',
  },

  // ---- Crime -----------------------------------------------------------------------------------------------------
  {
    id: 'crime',
    topic: 'crime',
    title: 'Crime, police and jail',
    summary: 'Stealing from other players is possible but risky. If the police catch you, you choose how to pay.',
    steps: [
      'In a public place, tap another player. You can try to pick their pocket if you are close.',
      'The result is rolled on the server. If caught, a "Police don catch you" pop-up appears.',
      'Choose to bail yourself out, or serve your time in jail. You can also try to escape.',
    ],
    where: 'The Police app on your phone shows your case. A banner shows while you are in jail.',
    tips: [
      'New players are protected for a while: nobody can rob you and you cannot rob.',
      'Keep your money in the bank. Thieves only take cash.',
      'Failed escapes make jail time and bail longer.',
    ],
    keywords: 'crime steal robbery pickpocket police jail bail escape protection thief',
  },

  // ---- Music -----------------------------------------------------------------------------------------------------
  {
    id: 'music',
    topic: 'music',
    title: 'Music and sound',
    summary: 'Benin Life has its own music, city sounds and club radio. Everyone in a club hears the same song at the same time.',
    steps: [
      'Tap the speaker at the top to mute or unmute everything.',
      'For finer control, open your Sim, then Settings, and use the Sound effects and Music switches.',
      'Go to a club to hear its playlist.',
    ],
    where: 'The speaker icon in the top bar, and Sim sheet, then Settings.',
    tips: ['On a phone, sound starts after your first tap. That is how browsers work.'],
    keywords: 'music sound mute radio dj playlist volume audio',
  },

  // ---- Politics --------------------------------------------------------------------------------------------------
  {
    id: 'politics',
    topic: 'politics',
    title: 'Benin Votes: run for office',
    summary: 'Run for Councillor, Chairman or Governor, campaign, and win a title, a daily salary and small powers. All parties are made up: no real parties or politicians.',
    steps: [
      'Open Phone, then Benin Votes. The top bar shows the phase: registration, campaign or voting day, with a countdown.',
      'During registration open the Elections tab and declare. Pick an office, write a short promise and choose a party (or run as an independent). Each office has a fee and requirements, so check the app: account age, Charisma level, no jail and no recent EFCC case. The Governor also needs a degree or a high career level. A Councillor runs in the ward where they live.',
      'During the campaign hold rallies at busy public places, put up posters, and ask players and gangs to back you. A rally costs money and trains your Charisma, and every player standing there adds points. Momentum shows who is rising: it is not votes.',
      'You can found your own fictional party. Real party names and real politicians are refused.',
      'Missing a requirement? A Godfather ticket (a very big fee on top of the normal one) lets you run anyway. The price is on the declare card. But everybody sees a 🎟️ on your card, EFCC may catch you during the campaign (you are disqualified and nothing is refunded), and reports against you count faster. It skips every requirement, even jail: if you have the money, nothing stops a Godfather.',
      'Vote buying is not allowed. If you see it, tap Report vote buying on the candidate. An admin reviews it and can disqualify.',
      'Winners are sworn in when voting closes. You get a title next to your name (Hon., Chairman, Gov.), a salary for every day of the term, and your term runs for a while before the next election.',
    ],
    where: 'Phone, then Benin Votes: Government, Elections, Vote and Results tabs.',
    tips: [
      'The Governor appoints six Commissioners, posts one government announcement a day, and sets ONE small policy for the term (cheaper keke on a day of the week, a lower council levy, a Fitness XP boost, slower hygiene decay).',
      'A Councillor can send one ward notice per term.',
      'Fees, windows, salaries and requirements can change. Check the app for the current numbers.',
    ],
    tour: ['politics'],
    keywords: 'politics election godfather ticket vote votes governor chairman councillor commissioner party campaign rally poster candidate endorse salary title hon gov policy announcement ward benin votes',
  },
  {
    id: 'vote',
    topic: 'politics',
    title: 'How to vote',
    summary: 'On voting day go to your ward polling unit and vote once for each office. Your ballot is secret.',
    steps: [
      'Open Benin Votes, then the Vote tab. It shows your ward and your polling unit.',
      'Polling units are places on the map. They open on voting day only, so you cannot travel there before then. Tap Go to your polling unit.',
      'At the unit, pick one candidate in each race (your ward Councillor, the Chairman and the Governor) and tap Cast my vote.',
      'You vote once per office. The counts are public only after voting closes. Results show on the Results tab.',
    ],
    where: 'Phone, then Benin Votes, then Vote. The polling desk at the unit has a Vote here card too.',
    tips: [
      'New accounts cannot vote: the account must be a few days old. Check the app for how many.',
      'You cannot vote while in jail or on the road.',
      'Low turnout is fine. A race with one candidate is still won, even with zero votes.',
    ],
    tour: ['politics'],
    keywords: 'vote voting polling unit ballot election day results secret turnout ward',
  },

  // ---- Safety ----------------------------------------------------------------------------------------------------
  {
    id: 'safety',
    topic: 'safety',
    title: 'Staying safe and reporting',
    summary: 'Benin Life is for players 18 and over. Keep it friendly, and tell us when something is wrong.',
    steps: [
      'Report a chat message: long-press it (or tap the three dots) and choose Report. A message reported by several people is hidden.',
      'Block someone from the same menu. Blocked players cannot message you. Unblock them in your Sim sheet, People tab.',
      'Report an ad with the Report button under it on a billboard.',
      'Bug or something serious? Use the Feedback app.',
    ],
    where: 'Chat and Messages menus, Sim sheet People tab, and the Feedback app.',
    tips: [
      'Never share your password. Benin Life will never ask for it.',
      'Do not click links from strangers. Billboard links warn you before you leave.',
    ],
    keywords: 'safety report block abuse harassment scam password privacy blocked',
  },

  // ---- Contact ---------------------------------------------------------------------------------------------------
  {
    id: 'contact',
    topic: 'contact',
    title: 'Contact us',
    summary: 'Got an idea, a bug or a question? We read everything.',
    steps: [
      'Open Phone, then Feedback. Choose Suggestion, Bug or Review, write your message and send.',
      'Replies show up as an alert in the game.',
      'You can also email code.devshalom@gmail.com.',
    ],
    where: 'Phone, then Feedback. Also Sim sheet, then Settings, then "Send feedback or report a bug".',
    tips: ['For a payment problem, include your payment reference.'],
    keywords: 'contact email feedback support bug suggestion help team developer',
  },
];

export function articleById(id: string | null | undefined): HelpArticle | undefined {
  return id ? HELP_ARTICLES.find((a) => a.id === id) : undefined;
}

/** Articles matching every word of the query (title, summary, steps, tips, keywords and topic name). */
export function searchArticles(query: string): HelpArticle[] {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (!words.length) return HELP_ARTICLES;
  return HELP_ARTICLES.filter((a) => {
    const topic = HELP_TOPICS.find((t) => t.id === a.topic)?.label ?? '';
    const hay = [a.title, a.summary, ...(a.steps ?? []), ...(a.tips ?? []), a.where ?? '', a.keywords ?? '', topic].join(' ').toLowerCase();
    return words.every((w) => hay.includes(w));
  });
}
