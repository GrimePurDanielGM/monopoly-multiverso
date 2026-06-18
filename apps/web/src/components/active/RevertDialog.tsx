import { useRef, useState } from 'react';
import { useDialogA11y } from '../../hooks/useDialogA11y';
import { isValidReason } from '../../lib/activeSelectors';

/** Diálogo para revertir un movimiento: exige un motivo (3–500). Accesible (foco/trap/Escape). */
export function RevertDialog({
  open,
  busy,
  onConfirm,
  onCancel,
}: {
  open: boolean;
  busy: boolean;
  onConfirm: (reason: string) => void;
  onCancel: () => void;
}) {
  const dialogRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const [reason, setReason] = useState('');
  useDialogA11y(open, dialogRef, { onEscape: () => !busy && onCancel(), initialFocusRef: inputRef });
  if (!open) return null;
  const valid = isValidReason(reason) && !busy;
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-4 sm:items-center" onClick={() => !busy && onCancel()}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-label="Revertir movimiento"
        className="w-full max-w-sm rounded-2xl border border-slate-700 bg-slate-900 p-5" onClick={(e) => e.stopPropagation()}>
        <h2 className="text-lg font-bold">Revertir movimiento</h2>
        <p className="mt-1 text-sm text-slate-400">Se creará un movimiento compensatorio. Indica un motivo.</p>
        <label className="mt-3 flex flex-col gap-1 text-sm">
          <span className="text-slate-400">Motivo (obligatorio)</span>
          <input ref={inputRef} value={reason} onChange={(e) => setReason(e.target.value)} maxLength={500} autoComplete="off"
            className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
        </label>
        <div className="mt-5 flex gap-2">
          <button type="button" onClick={onCancel} disabled={busy}
            className="min-h-[44px] flex-1 rounded-xl border border-slate-600 px-4 text-sm font-semibold disabled:opacity-40">
            Cancelar
          </button>
          <button type="button" onClick={() => valid && onConfirm(reason.trim())} disabled={!valid}
            className="min-h-[44px] flex-1 rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40">
            {busy ? 'Revirtiendo…' : 'Revertir'}
          </button>
        </div>
      </div>
    </div>
  );
}
