# Real Benin City landmarks to add (user request, 2026-10-05)

The user wants real, top-tier Benin places in the game (fun parks, lounges, hotels, houses, supermarkets, local food, cinemas…).
Research below was done with web search; addresses are as listed publicly. Map positions are **approximate** placements in
our 1000×1000 map space using the bearings in `docs/MAP_GEO.md` (King's Square = 500,500; ~80 units/km near the centre).
Verify each spot on OSM before seeding.

**DECIDED (user, 2026-10-06): use the ACTUAL names of real Benin places** (ShopRite, Kada Cinemas, Mama Ebo, Versus Lounge, Havana, Cube, Protea, Golden Tulip, Ogba Zoo, Samuel Ogbemudia Stadium, and so on), and set `world.real_brands` on by default. This covers top-tier clubs, lounges, hotels, malls, food places and premium housing areas (GRA: Aideyan Rd, Ikpokpan Rd, Ugbor, Estate Gate). Earlier note, kept for history:

~~Brand decision needed:~~ BRIEF.md said private businesses use fictional names. The user is now asking for real ones
(ShopRite, Kada, Mama Ebo). Real public landmarks (zoo, stadium, statue, park) are fine. For private brands, either use the real
name (the user's call, maybe with permission from the business — also a sponsorship opportunity, like Lagos Life's billboards)
or a close nod ("Shop-Right", "Kadda Cinema"). Default until the user decides: **real public landmarks now; private brands
behind a config flag `world.real_brands` (default off → nod names).**

## Shopping / supermarkets
| Place | Address | Map (approx) | Game use |
|---|---|---|---|
| Benin City Mall (ShopRite anchor, ~60 stores, Genesis Cinema inside) | Sapele Road | S on Sapele Rd, ~560,660 | supermarket (cheap bulk food, gadgets), cinema activity, mall stroll |
| Kada Plaza (Kada Cinemas + Kada Fried Chicken) | 111 (Old) Sapele Rd, Oka | S/SSE, ~545,640 | cinema (fun), fast food |

## Local food
| Place | Address | Map | Game use |
|---|---|---|---|
| Mama Ebo Pepper Rice | 88 Airport Rd | SW on Airport Rd, ~410,580 | buka: pepper rice (signature), jollof, swallow + soups; sells out fast at lunch (limited stock joke) |
| Chicken Republic (Ugbowo / Uselu, Siluko Rd, Airport Rd branches) | Ugbowo–Lagos Rd; 55 Airport Rd | N Uselu ~470,250; SW ~420,575 | fast food (brand flag) |
| Mr Bigg's | various | — | meat pie (brand flag) |

## Nightlife / lounges (GRA and Airport Rd)
| Place | Address | Map | Game use |
|---|---|---|---|
| Versus Lounge | 18 Guobadia Ave, off 1st Ugbor Rd, GRA | ~455,650 | lounge (night fun, social, street cred) |
| Havana | 34 Adesuwa Rd, GRA | ~470,660 | club |
| Club De Medici, Patricia Nightlife | GRA | GRA | club |
| Vibes Benin | 12 Ogbetuo Ave, off Ihama Rd, Oka | ~520,670 | club |
| Cube Nightlife | 46 Ihama Rd, off Airport Rd | ~440,620 | club |
| FJO Club & Lounge | off Ehaekpen St, Ekenwan Rd | ~360,560 | club |

## Hotels
| Place | Address | Map | Game use |
|---|---|---|---|
| Protea Hotel by Marriott Benin City Select Emotan | 4 Central Rd, off Sapele Rd | ~530,630 | hotel (luxury stay/sleep, pool, Nepo hangout) |
| Golden Tulip Essential (ex-Excalibur) | 23–27 Etete Rd, GRA | ~490,655 | hotel |
| Kawruky Hotel, Tovia Hotel & Suites | — | TBC | hotels |

## Fun parks / recreation / culture
| Place | Where | Map | Game use |
|---|---|---|---|
| Ogba Zoo & Nature Park (750 acres, state-owned, est. 1971) | Airport Rd / Ogba Rd, Oko | far SW past the airport, ~300,680 | day out: fun, social; Sunday family spot |
| Ramat Park (recreation park, est. 1985; flyover area now a hangout) | Ramat Park, Ikpoba Hill | already in game (680,415) | add "park stroll"/flyover hangout activity |
| Savealot Fun Park (rides, games) | Benin–Lagos Expressway after Ekiadolor Junction | off-map NW (remote_km) | amusement park, big fun |
| Philip Temile Nature Park | Benin City | TBC | nature park |
| Camplink Resort (water park, VR arcade) | Benin City | TBC | water park |
| Inno Child's World | Benin City | TBC | kids' amusement |
| Samuel Ogbemudia Stadium (home of Bendel Insurance FC) | Stadium Rd, off Ekenwan Rd, Ogogugbo | WSW ~380,545 | watch football (match days), fitness |
| Emotan Statue & shrine (1954) | directly opposite Oba Market | ~455,460 next to Oba Market | respectful photo spot / history activity |
| Edo State Government House | GRA | GRA | Gov filter pill |
| Museum of West African Art (MOWAA) | Benin City | TBC | culture |

## Houses / premium areas
- **GRA** (Ugbor, Ihama, Etete, Limit Rd, Amagba, Airport Rd corridor) is the premium area: plots ₦180M–₦450M in real life.
- **Aideyan Rd, Ikpokpan Rd, 2nd Ugbor Rd, Estate Gate (Airport Rd)** — luxury duplexes (e.g. 6-bed with pool ~₦500M).
- Game use: post-v1 housing ladder (buy/rent upgrades): "Estate Gate mansion", "Aideyan Rd duplex", "Ikpokpan apartment".

## Other cities (for the airport feature later)
User example: Kada Cinema. Later we'll collect top landmarks for Lagos, Abuja and Port Harcourt when the airport link is built.

## Plan
- Post-v1 step "Real Benin landmarks": new `locations` rows + scenes (SVG headers) + 3D city landmarks for the top ~10
  (Benin City Mall/ShopRite, Kada Plaza, Mama Ebo, Ogba Zoo, Samuel Ogbemudia Stadium, Emotan Statue, Protea, Versus Lounge,
  Savealot Fun Park, Golden Tulip), new activities (cinema, zoo trip, pool, match day, pepper rice), shop catalogues.
- Ask the user: real brand names or nod names? Which ~10 first?

## Sources
- Benin City Mall / ShopRite: https://www.facebook.com/Benincitymall/ , https://getoccupi.com/malls/benin-city-mall , https://www.nairaland.com/8084091/visit-new-shoprite-benin-city
- Kada Cinemas: https://hotels.ng/places/cinema-halls/3412-kada-cinema , https://www.waze.com/live-map/directions/ng/ed/benin-city/kada-plaza-cinema-and-entertainment-centre?to=place.ChIJn9xs55TTQBAR7FkEiAcLdxo
- Mama Ebo Pepper Rice: https://ranked.ng/place/mama-ebo-pepper-rice-z1bp1c , https://ng.africabz.com/edo/mama-ebo-pepper-rice-251763
- Hotels: https://www.tripadvisor.com/Hotels-g298361-Benin_City_Edo_State-Hotels.html , https://www.marriott.com/en-us/hotels/bnise-protea-hotel-benin-city-select-emotan/overview/ , https://triptap.com/places/ng/edo-state/benin-city/golden-tulip-essential-aka-excalibur-hotel-t04ea00a
- Fun parks: https://mindtrip.ai/attraction/benin-city-edo-state/savealot-fun-park/at-2Px2iYmg , https://en.wikipedia.org/wiki/Ogba_Zoo , https://en.wikipedia.org/wiki/Ramat_Park
- Nightlife: https://evendo.com/locations/nigeria/benin-city/bar/versus-lounge , https://blog.naijabased.fun/night-club-in-benin-city
- Stadium: https://en.wikipedia.org/wiki/Samuel_Ogbemudia_Stadium
- Emotan Statue: https://en.wikipedia.org/wiki/Emotan_Statue
- Premium areas: https://www.insidebenincity.com/hotels-in-benin-city-gra-visitor-guide.html , https://propertypro.ng/property-for-sale/in/edo/is-luxury
- Chicken Republic: https://ng.africabz.com/edo/chicken-republic-129407


## Update (user, 2026-10-06)
Keep the real names (ShopRite, Kada, Mama Ebo, Protea, clubs, Ogba Zoo, Ogbe Stadium, Emotan Statue) and mix in made-up local names. Add car dealers and top clubs — see docs/SHIP_TODAY.md (L2+ section).

## Seeded in L2 (2026-10-06, `supabase/migrations/20261006001300_places.sql`)
Real names as the user decided, plus two made-up local places. Positions follow the table above, nudged so
every pin stays ≥ 34 map units from the others (`map_geo_test.sql`). Every place has a 3D interior (docs/PLACES.md).

| id | Name | Type (scene) | Map (x, y) | Hours | What you can do |
|---|---|---|---|---|---|
| `emotan_statue` | Emotan Statue | monument | 468, 482 | – | Photo at the statue (free), hear Emotan's story (₦500), people-watch |
| `kada_plaza` | Kada Plaza (Kada Cinemas) | cinema | 554, 605 | 10 AM – midnight | Film ₦3,500, VIP recliner ₦9,000, arcade; Kada fried chicken, popcorn |
| `benin_city_mall` | Benin City Mall (ShopRite) | mall | 575, 665 | 9 AM – 10 PM | ShopRite aisles (cornflakes, noodles, soap, laptop...), Genesis Cinema, food court, mall stroll |
| `mama_ebo` | Mama Ebo Pepper Rice | buka | 405, 588 | – | Pepper rice + turkey ₦3,500 (**sells out 12–3 PM**, 40 % chance, "Pepper rice don finish!"), soups, jollof pack |
| `protea_hotel` | Protea Hotel Emotan | hotel | 509, 642 | – | Pool ₦7,500, luxury suite sleep ₦60,000, lounge cocktails ₦12,000, buffet ₦15,000 |
| `golden_tulip` | Golden Tulip Essential | hotel | 486, 670 | – | Same hotel actions |
| `ogba_zoo` | Ogba Zoo & Nature Park | zoo | 290, 690 | 8 AM – 6 PM | Lions & chimps ₦2,000, feed the ostriches, picnic, snacks |
| `ogbemudia_stadium` | Samuel Ogbemudia Stadium | stadium | 372, 532 | – | Match day (popular stand ₦1,000, VIP ₦10,000), jog the track, gate snacks |
| `club_360` | 360 Signature | club | 483, 706 | 9 PM – 5 AM | Club set (below) |
| `club_de_medici` | Club De Medici | club | 386, 638 | 9 PM – 5 AM | Club set |
| `rome_club` | Rome Night Club | club | 530, 735 | 9 PM – 5 AM | Club set |
| `cube_nightlife` | Cube Nightlife | club | 445, 582 | 9 PM – 5 AM | Club set |
| `versus_lounge` | Versus Lounge | club | 432, 616 | 9 PM – 5 AM | Club set |
| `owambe_republic` | Owambe Republic (made-up) | club | 735, 560 | 9 PM – 5 AM | Club set |
| `ighodalo_cars` | Ighodalo Car Deals | car_dealer | 528, 815 | – | Corolla, Kia Rio, Camry, Lexus RX; test drive, haggle |
| `sdd_motors` | SDD Motors | car_dealer | 585, 740 | – | Corolla, Camry, Lexus RX, brand-new Hilux; test drive, haggle |
| `tokunbo_lot` | Sapele Rd Tokunbo Lot (made-up) | car_dealer | 575, 850 | – | Corolla, Kia Rio (no showroom) |

**Club set** (all clubs, incl. Bronze Lounge and Kingdom Lounge, which now also open 9 PM – 5 AM): bar
(chapman, cold Star ₦1,500, champagne ₦45,000, pepper soup), dance floor (dance free, night out ₦3,000, **spray
money ₦50,000 — Risky**), DJ booth (**hype man shout-out ₦100,000, +5 street cred**), VIP section (**table +
bottle service ₦150,000, +3 street cred**, "VIP prices for your table"), sports screen, restroom.
**Cars**: Tokunbo Corolla ₦2.5M, fairly-used Kia Rio ₦1.8M, Camry "Muscle" ₦6.5M, Lexus RX 350 ₦18M,
brand-new Hilux ₦45M; paid bank first, then cash; one of each; any car unlocks the "Your car" ride mode.
Not seeded yet: Chicken Republic, Mr Bigg's, Savealot Fun Park, Camplink, MOWAA, Government House, other
clubs (Club Vibes, Havana, FJO), Otos Autos, Dominion Automobile, Mandilas Toyota.
