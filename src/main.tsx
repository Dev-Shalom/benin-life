import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import './styles/global.css';
import './styles/ui.css';
import './styles/screens.css';
import './styles/game.css';
import App from './App.tsx';
import { initAuth } from './state/game';

initAuth();

createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
