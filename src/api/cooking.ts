// Cooking and markets (step C, docs/COOKING.md; server: 20261030000100_cooking.sql). The server decides prices, ingredient checks and results.
import { rpc } from '../lib/api';

export interface GroceryPlace { id: string; name: string; open_now: boolean; hours: string }
export interface GroceryItem {
  id: string; name: string; icon: string | null; description: string;
  /** Oba Market today (changes every Benin day) */
  today: number;
  yesterday: number;
  /** the supermarket's fixed price */
  super: number;
  change_pct: number;
  owned: number;
}
export interface GroceryPrices {
  day: string; band_pct: number; markup_pct: number;
  market: GroceryPlace; supermarket: GroceryPlace;
  items: GroceryItem[];
}

export interface CookIngredient { id: string; name: string; icon: string | null; need: number; have: number }
export interface CookRecipe {
  id: string; name: string; emoji: string; blurb: string; sort: number;
  min_level: number; portions: number; minutes: number; base_minutes: number;
  hunger: number; energy: number; mood: number; xp: number;
  dish: string; dish_owned: number;
  cert: string | null; cert_name: string | null; cert_ok: boolean; level_ok: boolean;
  cost_per_portion: number;
  max_pots: number;
  ingredients: CookIngredient[];
}
export interface CookDish { id: string; name: string; icon: string | null; qty: number; effects: Record<string, number> }
export interface CookOverview {
  enabled: boolean; at_home: boolean; stove: boolean; home_name: string | null;
  skills_on: boolean; level: number | null; xp: number; level_from: number; level_next: number | null;
  xp_today: number; xp_cap: number;
  max_pot: number; pot_extra_pct: number; max_portions: number;
  catering: { cert: string; name: string; has: boolean; time_cut_pct: number; full_cut_pct: number };
  partner: { id: string; username: string } | null;
  shared_today: number; share_cap: number;
  kid_meal: boolean; kid_boost_pct: number;
  recipes: CookRecipe[];
  dishes: CookDish[];
}
export interface CookResult {
  message: string; recipe: string; dish: string; portions: number; pots: number; seconds: number; busy_until: string; owned: number;
  xp: { gain: number; level?: number; up?: boolean; capped?: boolean; easy?: boolean; off?: boolean };
}

export const groceryPrices = () => rpc<GroceryPrices>('grocery_prices');
export const cookOverview = () => rpc<CookOverview>('cook_overview');
export const cookStart = (recipe: string, pots = 1) => rpc<CookResult>('cook_start', { p_recipe: recipe, p_pots: pots });
export const cookShare = (item: string, qty = 1) =>
  rpc<{ message: string; left: number; shared_today: number; share_cap: number }>('cook_share', { p_item: item, p_qty: qty });
