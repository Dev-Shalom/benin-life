// Public API of the 3D home. Importing this does NOT load three.js; the canvas loads when
// <HomeView> mounts. See docs/HUD_HOME.md.
export * from './model';
export { HomeView, type HomeViewProps } from './HomeView';
