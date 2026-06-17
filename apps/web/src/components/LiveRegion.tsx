/** Región aria-live para anunciar cambios (copiado, conexión, errores) a lectores de pantalla. */
export function LiveRegion({ message, tone = 'info' }: { message: string; tone?: 'info' | 'success' | 'error' }) {
  const color = tone === 'error' ? 'text-rose-300' : tone === 'success' ? 'text-emerald-400' : 'text-slate-400';
  return (
    <p aria-live="polite" role="status" className={`min-h-[1rem] text-xs ${color}`}>
      {message}
    </p>
  );
}
