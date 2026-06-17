import { useState } from 'react';
import { useParams } from 'react-router-dom';
import { joinLink } from '../lib/config';

/**
 * Placeholder del Bloque 1. La sala SINCRONIZADA (snapshot + roster + fichas + ready)
 * se implementa en el Bloque 2 con get_lobby_snapshot. Aquí solo mostramos el código
 * y el enlace para compartir, sin leer estado del backend todavía.
 */
export function LobbyScreen() {
  const { code = '' } = useParams();
  const [copied, setCopied] = useState(false);
  const link = joinLink(code);

  async function copy() {
    try {
      await navigator.clipboard.writeText(link);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1500);
    } catch {
      /* sin portapapeles: el usuario puede copiar manualmente */
    }
  }

  return (
    <section className="flex flex-col gap-4">
      <h1 className="text-xl font-bold">Sala</h1>
      <div className="rounded-xl border border-slate-700 p-4 text-center">
        <p className="text-xs uppercase tracking-wide text-slate-500">Código</p>
        <p className="mt-1 text-3xl font-bold tracking-[0.3em]">{code}</p>
      </div>
      <div className="flex flex-col gap-2">
        <p className="text-sm text-slate-400">Comparte este enlace para que se unan:</p>
        <code className="block break-all rounded-lg bg-slate-800 px-3 py-2 text-sm">{link}</code>
        <button
          type="button"
          onClick={copy}
          className="rounded-lg border border-slate-600 px-3 py-2 text-sm active:bg-slate-800"
        >
          {copied ? 'Enlace copiado ✓' : 'Copiar enlace'}
        </button>
      </div>
      <p className="rounded-lg bg-slate-800 px-3 py-2 text-xs text-slate-400">
        La sala sincronizada (jugadores, fichas y preparados en vivo) llega en el Bloque 2.
      </p>
    </section>
  );
}
