import type { PublicToken } from '../lib/api';

interface TokenPickerProps {
  tokens: readonly PublicToken[];
  takenIds: ReadonlySet<string>;
  selectedId: string | null;
  disabled?: boolean;
  onSelect: (tokenId: string) => void;
}

/** Selector de ficha: marca como ocupadas las usadas por otros; permite la propia/ libres. */
export function TokenPicker({ tokens, takenIds, selectedId, disabled = false, onSelect }: TokenPickerProps) {
  return (
    <div role="radiogroup" aria-label="Ficha" className="grid grid-cols-4 gap-2">
      {tokens.map((t) => {
        const selected = selectedId === t.id;
        const takenByOther = takenIds.has(t.id) && !selected;
        const isDisabled = disabled || takenByOther;
        return (
          <button
            key={t.id}
            type="button"
            role="radio"
            aria-checked={selected}
            aria-label={t.label}
            disabled={isDisabled}
            onClick={() => onSelect(t.id)}
            className={`flex flex-col items-center gap-1 rounded-lg border p-2 disabled:opacity-30 ${
              selected ? 'border-indigo-400 bg-indigo-950' : 'border-slate-700 active:bg-slate-800'
            }`}
          >
            <span aria-hidden className="text-2xl leading-none">
              {t.icon}
            </span>
            <span className="truncate text-[10px] text-slate-400">{t.label}</span>
            {takenByOther && <span className="text-[9px] text-rose-400">ocupada</span>}
          </button>
        );
      })}
    </div>
  );
}
