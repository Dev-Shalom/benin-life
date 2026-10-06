// V1-4: typed wrappers for the shop, Bag, Chowdeck and rent RPCs (server: 20261005000800_shops.sql).
import { rpc } from '../lib/api';
import type { FoodMenu, GameState, InventoryItem, ShopList } from '../lib/types';

type Msg = { message: string };

export const shopList = (location?: string) => rpc<ShopList>('shop_list', location ? { p_location: location } : {});
export const shopBuy = (item: string, qty = 1) => rpc<Msg & { owned: number; spent: number }>('shop_buy', { p_item: item, p_qty: qty });
export const itemUse = (item: string) => rpc<Msg & { left: number }>('item_use', { p_item: item });
export const itemSell = (item: string, qty = 1) => rpc<Msg & { earned: number; left: number }>('item_sell', { p_item: item, p_qty: qty });
export const foodMenu = () => rpc<FoodMenu>('food_menu');
export const foodOrder = (item: string, qty = 1) => rpc<Msg & { paid: number }>('food_order', { p_item: item, p_qty: qty });
export const payRent = () => rpc<Msg & { paid: number; owed: number }>('pay_rent');

export const isEdible = (it: InventoryItem) => it.kind === 'use' && (it.category === 'food' || it.category === 'drink');

/** The most filling food in the Bag (for the "Eat something" wish chip). */
export function bestFood(state: GameState): InventoryItem | null {
  const food = (state.inventory ?? []).filter((i) => isEdible(i) && Number(i.effects.hunger ?? 0) > 0);
  food.sort((a, b) => Number(b.effects.hunger ?? 0) - Number(a.effects.hunger ?? 0));
  return food[0] ?? null;
}

export const ownsItem = (state: GameState, id: string) => (state.inventory ?? []).some((i) => i.id === id && i.qty > 0);

/** Shop/Bag section order and labels by item category. */
export const CATEGORY_ORDER: [string, string][] = [
  ['food', 'Food'], ['drink', 'Drinks'], ['hygiene', 'Hygiene'], ['health', 'Health'], ['phone', 'Phone'],
  ['gadget', 'Gadgets'], ['vehicle', 'Vehicles'], ['souvenir', 'Keepsakes'],
];

/** Can items be sold at this location scene? (config shop.sell_scenes, comma-separated) */
export function canSellAt(scene: string, sellScenes: string): boolean {
  return sellScenes.split(',').map((s) => s.trim()).includes(scene);
}
