import { useGame } from '../state/game';
import { Button, EmptyState } from '../ui';

export default function ErrorScreen({ message }: { message: string }) {
  const refresh = useGame((s) => s.refresh);
  const signOut = useGame((s) => s.signOut);
  return (
    <div className="center-screen">
      <div className="auth-card">
        <EmptyState
          icon="warning"
          title="Wahala don land"
          body={message}
          action={
            <div className="row" style={{ marginTop: 8 }}>
              <Button icon="refresh" onClick={() => void refresh()}>Try again</Button>
              <Button variant="ghost" onClick={() => void signOut()}>Log out</Button>
            </div>
          }
        />
      </div>
    </div>
  );
}
