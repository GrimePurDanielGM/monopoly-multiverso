import { useEffect } from 'react';
import { BrowserRouter } from 'react-router-dom';
import { AppRoutes } from './AppRoutes';
import { ensureAnonSession } from '../lib/session';
import { useSessionStore } from '../store/session';
import { useConnectionStore } from '../store/connection';

export function App() {
  const setStatus = useSessionStore((s) => s.setStatus);
  const setOnline = useConnectionStore((s) => s.setOnline);

  // Garantiza sesión anónima al arrancar (el uid vive solo dentro del SDK).
  useEffect(() => {
    let active = true;
    void ensureAnonSession().then((s) => {
      if (active) setStatus(s);
    });
    return () => {
      active = false;
    };
  }, [setStatus]);

  // Estado de conexión del dispositivo.
  useEffect(() => {
    const on = () => setOnline(true);
    const off = () => setOnline(false);
    window.addEventListener('online', on);
    window.addEventListener('offline', off);
    return () => {
      window.removeEventListener('online', on);
      window.removeEventListener('offline', off);
    };
  }, [setOnline]);

  return (
    <BrowserRouter>
      <AppRoutes />
    </BrowserRouter>
  );
}
