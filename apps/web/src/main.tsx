import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './app/App';
import './styles/index.css';

// El service worker se registra y su actualización se gestiona en <PwaPrompts/>
// (registerType: 'prompt'): UI discreta en lugar de window.confirm.

const el = document.getElementById('root');
if (!el) throw new Error('Falta #root');
createRoot(el).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
