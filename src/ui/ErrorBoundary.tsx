import { Component, type ErrorInfo, type ReactNode } from 'react';
import { EmptyState } from './EmptyState';
import { Button } from './Button';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
  /** Changing this clears a caught error (e.g. switching tabs). */
  resetKey?: unknown;
}
interface State {
  error: Error | null;
  key: unknown;
}

/** Keeps one broken panel from crashing the whole game. */
export class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null, key: undefined };

  static getDerivedStateFromError(error: Error): Partial<State> {
    return { error };
  }

  static getDerivedStateFromProps(props: Props, state: State): Partial<State> | null {
    if (props.resetKey !== state.key) return { error: null, key: props.resetKey };
    return null;
  }

  componentDidCatch(error: Error, info: ErrorInfo) {
    console.error('[panel crash]', error, info.componentStack);
  }

  render() {
    if (this.state.error) {
      return (
        this.props.fallback ?? (
          <EmptyState
            icon="warning"
            title="This part hit a snag"
            body="Something went wrong here. Try again, and if it keeps happening, let us know."
            action={
              <Button variant="ghost" size="sm" icon="refresh" onClick={() => this.setState({ error: null })}>
                Try again
              </Button>
            }
          />
        )
      );
    }
    return this.props.children;
  }
}
