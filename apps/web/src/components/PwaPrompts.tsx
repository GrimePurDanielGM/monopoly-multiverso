import { useEffect, useState } from 'react';
import { useRegisterSW } from 'virtual:pwa-register/react';

interface BeforeInstallPromptEvent extends Event {
  prompt: () => Promise<void>;
}

/** UI discreta: actualización disponible e instalación de la PWA. No promete offline completo. */
export function PwaPrompts() {
  const {
    needRefresh: [needRefresh, setNeedRefresh],
    updateServiceWorker,
  } = useRegisterSW();
  const [installEvt, setInstallEvt] = useState<BeforeInstallPromptEvent | null>(null);

  useEffect(() => {
    const onBip = (e: Event) => {
      e.preventDefault();
      setInstallEvt(e as BeforeInstallPromptEvent);
    };
    window.addEventListener('beforeinstallprompt', onBip);
    return () => window.removeEventListener('beforeinstallprompt', onBip);
  }, []);

  if (!needRefresh && !installEvt) return null;
  return (
    <div className="px-5">
      {needRefresh && (
        <div role="status" className="flex items-center justify-between gap-2 rounded-lg bg-indigo-950/70 px-3 py-1.5 text-xs text-indigo-100">
          <span>Hay una versión nueva.</span>
          <span className="flex gap-2">
            <button type="button" onClick={() => void updateServiceWorker(true)} className="font-semibold underline">
              Actualizar
            </button>
            <button type="button" onClick={() => setNeedRefresh(false)} className="text-indigo-300">
              Ahora no
            </button>
          </span>
        </div>
      )}
      {installEvt && (
        <div role="status" className="mt-1 flex items-center justify-between gap-2 rounded-lg bg-slate-800 px-3 py-1.5 text-xs text-slate-200">
          <span>Instala la app en tu dispositivo.</span>
          <button
            type="button"
            onClick={async () => {
              await installEvt.prompt();
              setInstallEvt(null);
            }}
            className="font-semibold underline"
          >
            Instalar
          </button>
        </div>
      )}
    </div>
  );
}
