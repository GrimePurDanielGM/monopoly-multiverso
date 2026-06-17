import type { PublicPlayer } from '../lib/api';

/** Selección de la identidad anterior por public_ref (nunca por id interno). */
export function RecoveryIdentityPicker({
  players,
  selected,
  onSelect,
}: {
  players: readonly PublicPlayer[];
  selected: string | null;
  onSelect: (ref: string) => void;
}) {
  if (players.length === 0) {
    return <p className="text-sm text-slate-400">No hay identidades recuperables en esta sala.</p>;
  }
  return (
    <div role="radiogroup" aria-label="Tu identidad anterior" className="flex flex-col gap-2">
      {players.map((p) => {
        const sel = selected === p.public_ref;
        return (
          <button
            key={p.public_ref}
            type="button"
            role="radio"
            aria-checked={sel}
            onClick={() => onSelect(p.public_ref)}
            className={`min-h-[44px] rounded-lg border px-3 text-left text-sm ${sel ? 'border-indigo-400 bg-indigo-950' : 'border-slate-700'}`}
          >
            {p.name}
          </button>
        );
      })}
    </div>
  );
}
