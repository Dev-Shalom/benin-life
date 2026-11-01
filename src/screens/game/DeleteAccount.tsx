// Fix it 8: "Delete my account" (Settings -> Account). Two steps: read what goes, then type DELETE.
// Server: edge function delete-my-account -> self_delete_start (audited) -> auth.admin.deleteUser (cascade). Cannot be undone.
import { useState } from 'react';
import { supabase } from '../../lib/supabase';
import { useGame } from '../../state/game';
import { useUi } from '../../state/ui';
import { Button, Sheet, toast } from '../../ui';

async function deleteMyAccount(confirm: string): Promise<string> {
  const { data, error } = await supabase.functions.invoke('delete-my-account', { body: { confirm } });
  if (!error && data?.ok) return String(data.message ?? 'Account deleted.');
  let msg = 'Delete failed. Check your connection and try again. Nothing was deleted.';
  try {
    const ctx = (error as { context?: Response } | null)?.context;
    const body = ctx ? await ctx.json() : data;
    if (body?.message) msg = String(body.message);
  } catch { /* keep the generic text */ }
  throw new Error(msg);
}

export function DeleteAccount() {
  const [step, setStep] = useState<0 | 1 | 2>(0);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const signOut = useGame((s) => s.signOut);
  const setOverlay = useUi((s) => s.setOverlay);
  const close = () => { if (!busy) { setStep(0); setText(''); } };
  const go = async () => {
    setBusy(true);
    try {
      const msg = await deleteMyAccount(text.trim());
      toast(msg, 'info');
      setOverlay(null);
      void signOut();
    } catch (e) {
      toast(e instanceof Error ? e.message : 'Delete failed.', 'bad');
      setBusy(false);
    }
  };
  return (
    <>
      <Button variant="ghost" block data-testid="delete-account-open" onClick={() => setStep(1)}>🗑️ Delete my account</Button>
      <Sheet open={step > 0} onClose={close} title="Delete my account" subtitle="This cannot be undone" size="tall">
        <div className="stack" data-testid="delete-account-sheet">
          {step === 1 ? (
            <>
              <p><b>This deletes your login and your whole life in Benin Life, for good.</b></p>
              <ul className="hint" style={{ paddingLeft: 18, margin: 0 }}>
                <li>Your Sim, money (cash and bank), bag, furniture, homes, cars, businesses and gang spot are gone.</li>
                <li>Your messages, friends and rank go with them.</li>
                <li>Nobody, not even the team, can bring it back. You can sign up again later, but you start from nothing.</li>
              </ul>
              <p className="hint">Just want a fresh start with the same login? Use "Start a new life" instead.</p>
              <div className="stack">
                <Button variant="danger" block onClick={() => setStep(2)}>I understand, continue</Button>
                <Button variant="ghost" block onClick={close}>Keep my account</Button>
              </div>
            </>
          ) : (
            <>
              <p>Type <b>DELETE</b> in capital letters to confirm.</p>
              <input className="input" value={text} onChange={(e) => setText(e.target.value)} placeholder="DELETE" autoCapitalize="characters" autoCorrect="off"
                aria-label="Type DELETE to confirm" data-testid="delete-account-input" />
              <div className="stack">
                <Button variant="danger" block disabled={text.trim() !== 'DELETE'} loading={busy} onClick={() => void go()}>Delete my account forever</Button>
                <Button variant="ghost" block disabled={busy} onClick={close}>Cancel</Button>
              </div>
            </>
          )}
        </div>
      </Sheet>
    </>
  );
}
