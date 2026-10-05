// Lazy wrapper for the live 3D turntable: three.js and react-three-fiber load only when this mounts.
import { lazy, Suspense } from 'react';
import type { StageProps } from './engine/Stage';
import { ErrorBoundary } from '../../ui';
import { AvatarPortrait } from './AvatarPortrait';

const Stage = lazy(() => import('./engine/Stage'));

export type AvatarStageProps = StageProps;

function Fallback({ className, style }: Pick<StageProps, 'className' | 'style'>) {
  return (
    <div className={`avatar-stage is-loading${className ? ' ' + className : ''}`} style={style}>
      <span className="avatar-stage__loader" aria-label="Loading your Sim" />
    </div>
  );
}

/** Drag-to-spin 3D character on a round platform. One per screen. */
export function AvatarStage(props: AvatarStageProps) {
  return (
    <ErrorBoundary
      fallback={
        // No WebGL (very old phones): show the still image instead.
        <div className={`avatar-stage is-static${props.className ? ' ' + props.className : ''}`} style={props.style}>
          <AvatarPortrait config={props.config} view="full" size={180} className="avatar-stage__still" />
        </div>
      }
    >
      <Suspense fallback={<Fallback className={props.className} style={props.style} />}>
        <Stage {...props} />
      </Suspense>
    </ErrorBoundary>
  );
}
