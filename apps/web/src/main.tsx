import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import { registerSW } from 'virtual:pwa-register';
import { App } from './app/App';
import './styles/index.css';

// Actualización controlada: cuando hay versión nueva, preguntamos al usuario.
registerSW({
  onNeedRefresh() {
    if (window.confirm('Hay una versión nueva. ¿Actualizar ahora?')) {
      window.location.reload();
    }
  },
});

const el = document.getElementById('root');
if (!el) throw new Error('Falta #root');
createRoot(el).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
