// H2 receipts (docs/RECEIPTS.md): the paper receipt shown right after a big purchase (any RPC result with
// `receipt`, see src/state/receipts.ts) and when a row is tapped in Bank → Receipts.
import { naira } from '../../lib/format';
import { useReceipts, type Receipt } from '../../state/receipts';
import { useUi } from '../../state/ui';
import { Button, Logo, Modal } from '../../ui';

const KIND_LABEL: Record<string, string> = {
  furniture: 'Furniture', car: 'Vehicle', shop: 'Shop', garage: 'Garage build', house: 'House move-in', boutique: 'Boutique',
};
const KIND_EMOJI: Record<string, string> = {
  furniture: '🛋️', car: '🚗', shop: '🛍️', garage: '🏗️', house: '🏠', boutique: '👗',
};

export function receiptKindEmoji(kind: string) {
  return KIND_EMOJI[kind] ?? '🧾';
}

export function receiptDate(iso: string): string {
  try {
    return new Date(iso).toLocaleString('en-GB', {
      timeZone: 'Africa/Lagos', day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit',
    }) + ' WAT';
  } catch {
    return iso;
  }
}

/** The paper itself (store, items, amount, date, ref, PAID stamp). */
export function ReceiptPaper({ r }: { r: Receipt }) {
  const bank = Number(r.meta?.from_bank ?? 0);
  const cash = Number(r.meta?.from_cash ?? 0);
  const tier = (r.meta?.dealer as { label?: string } | undefined)?.label;
  return (
    <div className="receipt" role="document" aria-label={`Receipt ${r.ref}`}>
      <div className="receipt__head">
        <span className="receipt__logo" aria-hidden>{r.seller ? receiptKindEmoji(r.kind) : <Logo size={30} title="" />}</span>
        <b className="receipt__store">{r.seller || 'Benin Life'}</b>
        <span className="receipt__city">Benin City, Edo State{tier ? ` · ${tier}` : ''}</span>
      </div>
      <div className="receipt__rule" />
      <dl className="receipt__meta">
        <div><dt>Receipt no.</dt><dd className="receipt__ref">{r.ref}</dd></div>
        <div><dt>Date</dt><dd>{receiptDate(r.created_at)}</dd></div>
        <div><dt>Type</dt><dd>{KIND_LABEL[r.kind] ?? r.kind}</dd></div>
      </dl>
      <div className="receipt__rule" />
      <div className="receipt__line">
        <span className="grow">{r.item_name}</span>
        <span>{naira(r.amount)}</span>
      </div>
      <div className="receipt__rule receipt__rule--dash" />
      <div className="receipt__total">
        <span>TOTAL</span>
        <b>{naira(r.amount)}</b>
      </div>
      {(bank > 0 || cash > 0) && (
        <div className="receipt__paid">
          {bank > 0 && <span>Bank transfer {naira(bank)}</span>}
          {cash > 0 && <span>Cash {naira(cash)}</span>}
        </div>
      )}
      <p className="receipt__thanks">Thank you for your patronage!</p>
      <span className="receipt__stamp" aria-label="Paid">PAID</span>
    </div>
  );
}

export function ReceiptSheet() {
  const r = useReceipts((s) => s.open);
  const close = useReceipts((s) => s.close);
  const openPhone = useUi((s) => s.openPhone);
  const phoneOpen = useUi((s) => s.overlay === 'phone' && s.phoneApp === 'bank');
  return (
    <Modal open={r !== null} onClose={close}
      actions={
        <>
          {!phoneOpen && <Button variant="ghost" onClick={() => { useReceipts.getState().requestList(true); close(); openPhone('bank'); }}>All receipts</Button>}
          <Button onClick={close}>Done</Button>
        </>
      }>
      {r && <ReceiptPaper r={r} />}
    </Modal>
  );
}
