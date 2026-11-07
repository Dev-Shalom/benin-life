# City check (Phase 0 bug sweep of the 3D map)

`npm run city-check` (plain `node scripts/city-check.mjs`, Node 22+, no dependencies; `-v` lists more offenders, `--json` prints the counts). It loads the layout exactly as the game builds it (`src/art/city3d/engine/layout.ts`) and exits 1 on any violation. CI: `.github/workflows/city-check.yml` runs it on pushes and PRs that touch `src/art/city3d`, `src/art/map` or the script.

## What is checked
| Check | Rule |
|---|---|
| Buildings on a carriageway / on the pavement | No house or OSM footprint (roof overhang included) may touch the paved band: carriageway half-width + kerb strip (`KERB` in `engine/roadnet.ts`). Exact distance to the road centre lines, including the roads that run on past the map edge. |
| Buildings overlapping | No house over another house or an OSM footprint (touching walls are fine); OSM footprints may not overlap each other; nothing over a landmark model. |
| Landmark models on a road | Footprints in `engine/footprints.ts` (museum, palace, UBTH, hub, police, terminal, markets, huts, motor parks ...) stay off the road and pavement. |
| Props | Trees and palms (trunk), street lamps and parked danfos: not on a carriageway, not inside a building. |
| Traffic | Every moving vehicle's full box, swept along its whole lane every 1.5 units, stays off all footprints and keeps every corner on tarmac; four minutes are simulated (0.25 s steps) to prove no two vehicles ever overlap. |
| Place markers | Every seeded place (`dev/fixture.ts` + coming-soon pins), as drawn by `snapPlace`, is not inside a house and (non-street places) not in the carriageway. `data/anchors.ts` must list every fixture place at the same spot. |

Billboards come from the database at run time, so they are not in this audit (`/dev/city?boards=1` still shows them against the roads).

## How the layout keeps these true
- `engine/roadnet.ts`: exact clearance to road edges (replaces the old circle approximation, which let roofs creep onto the kerb).
- `engine/layout.ts`: every OSM and generated footprint is tested against the paved band, the landmark footprints, motor parks, the place markers (`data/anchors.ts`) and every footprint already placed (polygon overlap). Trees and lamps are tested the same way. Spurs stop at landmark models.
- Motor parks (`PAD_SEEDS`) sit on junctions in the seed; each is moved to the nearest clear ground (the pad disc, shelter and parked danfos follow; `layout.pads`).
- Traffic: one speed and equal spacing per lane, so nothing overtakes or drives through the car in front. A road carries traffic only on the stretch where it is clear of every wider road, so two streams never cross; vehicles fade out and in at the ends of a stretch (`vehicleAt`, scale `k`). The Ramat Park queues stop 18 units from the roundabout island and free traffic stays out of them.
- Place markers seeded on a carriageway or inside a house are nudged to clear ground (`snapPlace`, a few map units) when `CityScene` draws them. Street, PoS and motor-park places may stay on their road.
- The Oregbeni and Uselu market grounds moved next to their place markers (`MARKETS` in `mapGeo.ts`), on clear ground; the farm huts moved off the dirt road (`FARM_HUTS`).

## Before / after (seed 20261005)
| Check | Before | After |
|---|---|---|
| Buildings on a carriageway | 12 | 0 |
| Buildings on the pavement | 74 | 0 |
| Houses overlapping houses / OSM | 151 | 0 |
| OSM footprints overlapping each other | 9 | 0 |
| Buildings inside a landmark (palace compound ...) | 28 | 0 |
| Landmark models on a road | 2 | 0 |
| Trees on a carriageway / inside a building | 9 / 11 | 0 / 0 |
| Street lamps on a carriageway / inside a building | 23 / 3 | 0 / 0 |
| Parked danfos on a carriageway / inside a building | 20 / 1 | 0 / 0 |
| Traffic through buildings / off the tarmac | 0 / 0 | 0 / 0 |
| Vehicles driving through each other | 585 | 0 |
| Place markers inside a house / on a carriageway | 3 / 5 | 0 / 0 |

Counts now: ~930 houses (960 before; a failed spot is retried nudged and 20% smaller), 1,022 OSM footprints (1,016; footprints next to a street are nudged up to 3 units off the pavement before being dropped), 190 vehicles (203). Dropped OSM footprints (`layout.osmDrops`): inside King's Square, palace or other landmark zones 3,331; centre on the carriageway 584; too small 178; corner in a landmark zone 82; still on the road after nudging 74; overlapping a landmark or marker 10. No named landmark footprint is dropped (the audit checks them).

## Adding things
- New landmark model: add its footprint to `MODEL_FOOTPRINTS` (`engine/footprints.ts`), then run the check.
- New place: add it to the migration, regenerate `dev/fixture.ts`, add a line to `data/anchors.ts`.
- New road: add it to `ROADS`; the check will show what now sits on it.
