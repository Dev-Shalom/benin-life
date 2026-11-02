// One-line text for the audit rows the Grant toolbox writes (docs/ADMIN_GRANTS.md). Used by Audit and the player's Admin history.
type D = Record<string, unknown>;
const obj = (v: unknown): D => (v && typeof v === 'object' ? (v as D) : {});
const reason = (d: D) => (d.reason ? ` · “${String(d.reason)}”` : '');
const lv = (v: D) => `${v.title ?? v.track ?? '—'} L${v.level ?? '?'}${v.xp != null ? ` (${v.xp} XP)` : ''}`;

export function grantSummary(action: string, data: unknown): string {
  const d = obj(data);
  switch (action) {
    case 'grant_career': return `Career ${lv(obj(d.old))} → ${lv(obj(d.new))}${reason(d)}`;
    case 'career_remove': return `Job removed (${d.title ?? d.track})${reason(d)}`;
    case 'refill_needs': return `Refilled ${Array.isArray(d.needs) ? (d.needs as string[]).join(', ') : 'needs'}${reason(d)}`;
    case 'clear_states': return `Cleared ${Array.isArray(d.cleared) ? (d.cleared as string[]).join(', ') : 'states'}${reason(d)}`;
    case 'jail_put': return `Jailed for ${d.seconds} s${reason(d)}`;
    case 'jail_release': return `Released from jail${reason(d)}`;
    case 'set_numbers': {
      const o = obj(d.old), n = obj(d.new);
      return `Street cred ${o.street_cred} → ${n.street_cred}, wanted ${o.wanted} → ${n.wanted}${reason(d)}`;
    }
    case 'clear_debts': return `Cleared debt (rent ${d.rent_owed ?? '—'}, tax ${d.tax_owed ?? '—'})${reason(d)}`;
    case 'set_yahoo_rank': return `Yahoo ${d.old_rank} → ${d.new_rank}${reason(d)}`;
    case 'grant_item': case 'grant_car': case 'take_item': return `${action === 'take_item' ? 'Took' : 'Gave'} ${d.qty} × ${d.name} (${d.old} → ${d.new})${reason(d)}`;
    case 'grant_furniture': case 'take_furniture': return `${action === 'take_furniture' ? 'Took' : 'Gave'} ${d.qty} × ${d.name} (${d.old} → ${d.new})${reason(d)}`;
    case 'grant_garage': return `Garage: ${d.name}${reason(d)}`;
    case 'remove_garage': return `Garage removed${reason(d)}`;
    case 'grant_wardrobe': case 'take_wardrobe': return `${action === 'take_wardrobe' ? 'Took' : 'Gave'} clothes: ${d.name}${reason(d)}`;
    case 'grant_hustle_pass': return `${d.hours} h of the ${d.pass} pass${reason(d)}`;
    case 'take_hustle_pass': return `Ended the ${d.pass} pass${reason(d)}`;
    case 'grant_business_level': return `${d.name}: level ${obj(d.old).level} → ${obj(d.new).level}, staff ${obj(d.old).staff} → ${obj(d.new).staff}${reason(d)}`;
    case 'grant_company': return `Gave company ${d.name}${reason(d)}`;
    case 'grant_company_set': return `${d.name}: size ${obj(d.old).format} → ${obj(d.new).format}, staff ${obj(d.old).staff} → ${obj(d.new).staff}${reason(d)}`;
    case 'set_home': return `Home ${d.old} → ${d.new}${reason(d)}`;
    case 'grant_property': return `Gave property ${d.name}${reason(d)}`;
    case 'take_property': return `Took property ${d.name}${reason(d)}`;
    case 'grant_land': return `Gave ${d.plots} plot(s) in ${d.market} (${d.old} → ${d.new})${reason(d)}`;
    case 'take_land': return `Took ${d.plots} plot(s) in ${d.market} (${d.old} → ${d.new})${reason(d)}`;
    case 'grant_crew': return `Gang ${d.name}: ${d.old_rank ?? 'not in'} → ${d.new_rank}${reason(d)}`;
    case 'crew_remove': return `Removed from ${d.name}${reason(d)}`;
    case 'grant_chief_title': return `Chief title ${obj(d.new).name}${reason(d)}`;
    case 'remove_chief_title': return `Chief title ${d.name} removed${reason(d)}`;
    case 'grant_course': return `Course completed: ${d.name}${reason(d)}`;
    case 'reset_course': return `Course reset: ${d.name}${d.cert_revoked ? ' (certificate taken back)' : ''}${reason(d)}`;
    default: return '';
  }
}
