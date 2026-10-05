# Benin City geography check (2026-10-05)

The user asked the lead to check the real map instead of guessing. Sources:
- OpenStreetMap: Overpass road geometry and landmark nodes/ways, plus Nominatim lookups.
- Wikipedia coordinates for the Royal Palace of the Oba of Benin and for UBTH.

All offsets below are in km from King's Square (6.33297 N, 5.62262 E). E is east and N is north.

## Verified facts
- **Oba's Palace:** 6.33222 N, 5.62000 E, which is **E-0.29 N-0.08**. It sits just **west (slightly south)** of King's Square, outside the ring.
  - **The old map was wrong:** it had the palace at SSE.
- **Oba Market:** OSM marketplace at **E-0.32 N+0.24**, just **north-west** of King's Square. (Correct before.)
- **Igun Street:** OSM residential way at **E+0.78 N+0.38**, **east-north-east** of King's Square, between Akpakpava Rd and Sakponba Rd.
  - **The old map was wrong:** it had Igun Street to the SE.
- **UBTH:** 6.39059 N, 5.61217 E, which is **E-1.16 N+6.37**, at Ugbowo, almost due **north**.
  - **Watch out:** an OSM node on Ikpokpan Rd in GRA is a different site.
- **UNIBEN Ugbowo:**
  - The campus is around **E-0.4…+0.3, N+7.1…7.9**. Ekosodin (the back gate area) is at **E-0.66 N+9.26**.
  - UNIBEN's *Ekenwan campus* is at E-2.45 N+0.07. It is not the main campus.
- **Uselu:**
  - The town is at **E-1.32 N+5.57**. Uselu motor park is at **E-0.58 N+3.90**.
  - Both are north, on the Lagos road.
- **Oluku:** **E-2.84 N+12.9**, far north. The Lagos road and the bypass meet here.
- **Ramat Park and the flyover:** **E+4.28 N+1.97** (ENE). Oregbeni village is at E+3.77 N+1.79, and Ikpoba village at E+3.03 N+1.88.
  - The Ikpoba River runs north–south at about **E+3**, between the end of Akpakpava Rd and Ramat Park.
- **Aduwawa:** **E+6.24 N+3.34** (ENE), on the Benin–Auchi road.
- **Santana Market:** **E+1.10 N-4.58**, south, along Sapele Rd.
- **Police:**
  - Nigeria Police HQ / State CID: **E+0.26 N-1.40**.
  - Zone 5 HQ: E+0.42 N-3.21.
  - Officers' Mess: E+0.41 N-2.08.
  - All of these are south, in the GRA.
- **GRA:** south of the centre, between Airport Rd and Sapele Rd, at roughly E-0.5…+0.5, N-1.5…-3.2. Ikpokpan Rd and Aideyan Cres are both there.
- **Benin Airport:** **E-2.55 N-1.75** (SW).
- **Iguobazuwa:** far to the north-west (6.563 N, 5.355 E). The Upper Siluko Rd heads that way.

## Road bearings out of King's Square
Bearings are in degrees, clockwise from north.

| Road | Bearing | Goes to |
|---|---|---|
| Mission Rd | 31 (NNE) | New Benin, Upper Mission Rd |
| Akpakpava Rd | 52 (NE) | Ikpoba bridge, Ikpoba Hill, Ramat Park |
| Benin–Auchi Rd (from Ramat) | ENE | Aduwawa |
| Benin–Agbor Rd (from Ramat) | ~93 (E, then ESE) | |
| Sakponba Rd | 125 (SE/ESE), long | Upper Sakponba |
| Benin–Sapele Rd | 165 (SSE) | Santana Market |
| Airport Rd | 221 (SW) | Airport |
| Ekenwan (Ekenhuan) Rd | 254 (WSW) | |
| Siluko Rd | 314 (**NW**, not SW) | Upper Siluko Rd, on NW towards Iguobazuwa |
| Lagos Rd (Uselu / Ugbowo–Lagos Rd) | ~350 (N, slightly W) | Uselu, Ugbowo (UBTH, UNIBEN), Oluku, then the bypass towards Lagos |

The circular roads run roughly north–south east of the centre:
- First East Circular: about E+1.1…1.4
- Second East Circular: about E+1.7
- Third East Circular: about E+2.4

## Corrected map positions
The map space is 1000×1000 with north up, and King's Square is at (500,500). Distances are compressed radially to fit the map: about 80 units/km near the centre, and progressively less towards the edge. Directions and relative order follow the real data.

Pins sit just outside the drawn Ring Road (radius about 55 units). They are at least about 35 units apart so they don't overlap.

| id | old | **new** | why |
|---|---|---|---|
| national_museum | 500,500 | 500,500 | centre |
| oba_market | 445,465 | **448,452** | NW, just outside the ring |
| oba_palace | 545,560 | **432,512** | W (slightly S); the palace compound art must move here |
| ring_road_pos | 565,465 | **520,440** | on the ring, north side (fictional) |
| igun_street | 590,590 | **580,470** | ENE, between Akpakpava and Sakponba |
| mama_osas_buka | 455,545 | **480,565** | fictional, makes room for the palace |
| mission_rd_flats | 520,410 | **530,405** | on Mission Rd (NNE) |
| mercy_clinic | 545,380 | **560,365** | New Benin side |
| new_benin_market | 585,335 | **595,350** | NNE up Mission Rd |
| new_benin_pos | 630,365 | **645,375** | |
| uselu_park | 340,365 | **450,270** | N on the Lagos Rd (OSM Uselu motor park) |
| uselu_market | 385,330 | **480,235** | N |
| fresh_cut_salon | 420,295 | **515,290** | Uselu |
| ubth | 305,250 | **440,165** | N, Ugbowo |
| uniben | 255,205 | **480,125** | N, Ugbowo |
| wifi_joint | 305,170 | **400,135** | Ugbowo |
| back_gate_joint | 215,165 | **455,75** | Ekosodin, N of the campus |
| oluku_park | 130,85 | **390,40** | far N/NNW |
| ramat_park | 705,375 | **680,415** | ENE, east of the Ikpoba River |
| oregbeni_market | 745,470 | **700,465** | Ikpoba Hill |
| aduwawa_park | 880,400 | **820,335** | ENE on the Auchi Rd |
| aduwawa_room | 850,505 | **860,385** | Aduwawa |
| third_east | 680,560 | **665,520** | Third East Circular, E |
| ekiosa_market | 620,630 | **595,575** | SE off Sakponba Rd |
| baba_shrine | 680,665 | **640,615** | Sakponba side (fictional) |
| upper_sakponba | 735,745 | **700,665** | further SE along Sakponba Rd |
| police_hq | 380,600 | **510,600** | S, GRA (State CID) |
| bronze_bank | 415,560 | **470,625** | GRA (fictional) |
| kingdom_lounge | 325,580 | **420,650** | GRA (fictional) |
| gra_duplex | 340,655 | **450,690** | GRA |
| sapele_pos | 510,650 | **545,640** | on Sapele Rd (SSE) |
| santana_market | 470,700 | **560,700** | S on Sapele Rd |
| bronze_lounge | 540,765 | **560,770** | Sapele Rd nightlife |
| benin_airport | 235,470 | **330,615** | SW at the end of Airport Rd |
| ekenwan_room | 205,620 | **298,562** | WSW on Ekenwan Rd |
| siluko_rd | 330,735 | **378,378** | **NW**, not SW |
| iguobazuwa_farm | 40,700 | **40,300** | NW edge, off-map via Upper Siluko Rd |
| bronze_tech_hub (P2) | – | **535,190** | Ugbowo tech cluster near UNIBEN (fictional) |

## District areas (for the map art)
| District | Where |
|---|---|
| oredo | the ring |
| new_benin | NNE |
| uselu | N |
| ugbowo | far N |
| oluku | far N/NNW |
| ikpoba_hill | ENE, across the river |
| aduwawa | far ENE |
| third_east | E |
| sakponba | SE |
| upper_sakponba | far SE |
| sapele_rd | S/SSE |
| gra | S/SSW |
| airport_rd | SW |
| ekenwan | WSW |
| siluko | NW |
| iguobazuwa | off-map NW |

The exit signs need these changes:
- **LAGOS:** goes N via Oluku.
- **AUCHI:** goes ENE via Aduwawa.
- **AGBOR / Asaba:** goes E/ESE from Ramat.
- **SAPELE / Warri:** goes S.
- **Iguobazuwa / farm:** a sign NW on Upper Siluko Rd.

## Applied (P1-MAP, 2026-10-05)
- `supabase/migrations/20261005000100_map_geo.sql` moves every seeded pin to the table above, with two small nudges so pins and labels never collide at phone zoom:
  - **ring_road_pos:** 540,452 instead of 520,440. It is still on the ring, now on the NE side between Mission Rd and Akpakpava Rd.
  - **police_hq:** 510,604 instead of 510,600.
- `bronze_tech_hub` (535,190) is left to its Phase 2 owner. Nothing in the map art sits on that spot.
- The map art (`src/art/map/mapGeo.ts`) draws the roads, river, palace, campus, UBTH, airport, GRA, farmland, district tints/labels and exit signs to match this file.
- `supabase/tests/map_geo_test.sql` checks every position and the main direction facts.
- `node scripts/render-map.mjs <outDir>` renders the map (day/night, full, phone, zoomed) and prints label/pin collision diagnostics.
