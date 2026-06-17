import { useRef, useState } from 'react';
import { joinLink } from '../lib/config';
import { copyToClipboard, shareOrCopy } from '../lib/share';
import { QrCode } from './QrCode';
import { LiveRegion } from './LiveRegion';
import { useDialogA11y } from '../hooks/useDialogA11y';

/** Compartir la sala: código, enlace, QR, copiar y compartir. El QR solo contiene la URL. */
export function SharePanel({ code }: { code: string }) {
  const link = joinLink(code);
  const [msg, setMsg] = useState('');
  const [zoom, setZoom] = useState(false);
  const zoomRef = useRef<HTMLDivElement>(null);
  const zoomCloseRef = useRef<HTMLButtonElement>(null);
  useDialogA11y(zoom, zoomRef, { onEscape: () => setZoom(false), initialFocusRef: zoomCloseRef });

  const announce = (m: string) => {
    setMsg(m);
    window.setTimeout(() => setMsg(''), 2500);
  };

  return (
    <section aria-label="Compartir partida" className="flex flex-col gap-3 rounded-xl border border-slate-700 p-4">
      <h2 className="text-sm font-bold text-slate-200">Compartir</h2>

      <div className="flex items-center justify-between gap-2">
        <span className="text-sm">
          Código <span className="font-semibold tracking-[0.2em] text-slate-100">{code}</span>
        </span>
        <button
          type="button"
          onClick={async () => (await copyToClipboard(code)) && announce('Código copiado')}
          className="min-h-[44px] rounded-lg border border-slate-600 px-3 text-sm"
        >
          Copiar código
        </button>
      </div>

      <code className="block break-all rounded-lg bg-slate-800 px-3 py-2 text-xs">{link}</code>
      <div className="flex gap-2">
        <button
          type="button"
          onClick={async () => (await copyToClipboard(link)) && announce('Enlace copiado')}
          className="min-h-[44px] flex-1 rounded-lg border border-slate-600 px-3 text-sm"
        >
          Copiar enlace
        </button>
        <button
          type="button"
          onClick={async () => {
            const m = await shareOrCopy({ title: 'Únete a mi partida', text: `Código: ${code}`, url: link });
            if (m === 'clipboard') announce('Enlace copiado');
          }}
          className="min-h-[44px] flex-1 rounded-lg bg-indigo-600 px-3 text-sm font-semibold"
        >
          Compartir
        </button>
      </div>

      <div className="flex flex-col items-center gap-1">
        <button type="button" onClick={() => setZoom(true)} aria-label="Ampliar código QR" className="rounded-lg">
          <QrCode url={link} size={160} />
        </button>
        <span className="text-[11px] text-slate-500">Pulsa el QR para ampliarlo</span>
      </div>

      <LiveRegion message={msg} tone="success" />

      {zoom && (
        <div
          ref={zoomRef}
          role="dialog"
          aria-modal="true"
          aria-label="Código QR ampliado"
          className="fixed inset-0 z-50 flex flex-col items-center justify-center gap-3 bg-black/80 p-6"
          onClick={() => setZoom(false)}
        >
          <div className="rounded-2xl bg-white p-4" onClick={(e) => e.stopPropagation()}>
            <QrCode url={link} size={280} />
          </div>
          <button
            ref={zoomCloseRef}
            type="button"
            onClick={(e) => {
              e.stopPropagation();
              setZoom(false);
            }}
            className="min-h-[44px] rounded-xl bg-white/10 px-5 text-sm font-semibold text-white"
          >
            Cerrar
          </button>
        </div>
      )}
    </section>
  );
}
