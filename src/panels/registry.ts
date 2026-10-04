// Phase 0 — do not edit. Panels are discovered by file name so missing ones never break the build.
import { lazy, type ComponentType, type LazyExoticComponent } from 'react';
import type { PanelId, PanelProps } from '../lib/types';

const modules = import.meta.glob<{ default: ComponentType<PanelProps> }>('./*Panel.tsx');

export const PANEL_FILES: Record<PanelId, string> = {
  activities: 'ActivitiesPanel',
  jobs: 'JobsPanel',
  shop: 'ShopPanel',
  market_p2p: 'MarketPanel',
  housing: 'HousingPanel',
  inventory: 'InventoryPanel',
  bank: 'BankPanel',
  pos: 'PosPanel',
  loans: 'LoansPanel',
  esusu: 'EsusuPanel',
  farm: 'FarmPanel',
  hospital: 'HospitalPanel',
  babalawo: 'BabalawoPanel',
  police: 'PolicePanel',
  rob: 'RobPanel',
  crimes: 'CrimesPanel',
  chat: 'ChatPanel',
  messages: 'MessagesPanel',
  profile: 'ProfilePanel',
  wallet: 'WalletPanel',
  airport: 'AirportPanel',
};

export const PANEL_LABELS: Record<PanelId, string> = {
  activities: 'Wetin to do',
  jobs: 'Work & Hustle',
  shop: 'Buy',
  market_p2p: 'Market',
  housing: 'House',
  inventory: 'Bag',
  bank: 'Bank',
  pos: 'PoS',
  loans: 'Loan',
  esusu: 'Esusu',
  farm: 'Farm',
  hospital: 'Hospital',
  babalawo: 'Babalawo',
  police: 'Police',
  rob: 'Rob',
  crimes: 'Case File',
  chat: 'Gist',
  messages: 'Messages',
  profile: 'Profile',
  wallet: 'Wallet',
  airport: 'Airport',
};

const cache = new Map<PanelId, LazyExoticComponent<ComponentType<PanelProps>>>();

export function hasPanel(id: PanelId): boolean {
  return Boolean(modules[`./${PANEL_FILES[id]}.tsx`]);
}

export function loadPanel(id: PanelId): LazyExoticComponent<ComponentType<PanelProps>> | null {
  const loader = modules[`./${PANEL_FILES[id]}.tsx`];
  if (!loader) return null;
  let comp = cache.get(id);
  if (!comp) {
    comp = lazy(loader);
    cache.set(id, comp);
  }
  return comp;
}
