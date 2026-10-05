import { useGame } from '../state/game';
import { Button, EmptyState } from '../ui';
import { Logo } from './Brand';

export default function ErrorScreen({ message }: { message: string }) {
  const refresh = useGame((s) => s.refresh);
  const signOut = useGame((s) => s.signOut);
  return (
    <div className="center-screen">
      <div className="center-screen__brand">
        <Logo size={44} />
        <span>Benin Life</span>
      </div>
      <div className="auth-card">
        <EmptyState
          icon="warning"
          title="Something went wrong"
          body={message}
          action={
            <div className="error-actions">
              <Button icon="refresh" onClick={() => void refresh()}>Try again</Button>
              <Button variant="ghost" onClick={() => void signOut()}>Log out</Button>
            </div>
          }
        />
      </div>
    </div>
  );
}
