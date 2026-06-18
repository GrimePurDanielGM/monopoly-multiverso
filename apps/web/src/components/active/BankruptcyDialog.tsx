import { useRef, useState } from 'react';
import { useDialogA11y } from '../../hooks/useDialogA11y';
import type { ActiveSnapshot } from '../../lib/activeSnapshot';
import type { BankruptcyKind } from '../../lib/api';
import { activeCreditors } from '../../lib/activeSelectors';

/** Diálogo: el jugador se declara en bancarrota (frente a banca o frente a un acreedor + motivo). */
export function BankruptcyDialog({
  open, snap, busy, onConfirm, onCancel,
}: {
  open: boolean;
  snap: ActiveSnapshot;
  busy: boolean;
  onConfirm: (kind: BankruptcyKind, creditorRef: string | null, reason: string) => void;
  onCancel: () => void;
}) {
  const cancelRef = useRef<HTMLButtonElement>(null);
  const dialogRef = useRef<HTMLDivElement>(null);
  const [kind, setKind] = useState<BankruptcyKind>('to_bank');
  const [creditor, setCreditor] = useState('');
  const [reason, setReason] = useState('');
  useDialogA11y(open, dialogRef, { onEscape: onCancel, escapeEnabled: !busy, initialFocusRef: cancelRef });

  const creditors = activeCreditors(snap);
  const validReason = reason.trim().length >= 3;
  const validCreditor = kind === 'to_bank' || (creditor !== '' && creditors.some((c) => c.public_ref === creditor));
  const valid = validReason && validCreditor;

  if (!open) return null;
  return (
    <div className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-4 sm:items-center" onClick={() => !busy && onCancel()}>
      <div ref={dialogRef} role="dialog" aria-modal="true" aria-labelledby="bankruptcy-title"
        className="w-full max-w-sm rounded-2xl border border-slate-700 bg-slate-900 p-5" onClick={(e) => e.stopPropagation()}>
        <h2 id="bankruptcy-title" className="text-lg font-bold">Declararme en bancarrota</h2>
        <p className="mt-1 text-sm text-slate-300">Tu anfitrión deberá aprobarlo. Quedarás como espectador y podrás seguir consultando la partida.</p>

        <fieldset className="mt-3 flex flex-col gap-2 border-0 p-0">
          <legend className="mb-1 text-xs font-semibold text-slate-200">Tipo</legend>
          <label className="flex items-center gap-2 text-sm">
            <input type="radio" name="bk-kind" checked={kind === 'to_bank'} disabled={busy} onChange={() => setKind('to_bank')} />
            <span>Bancarrota frente a la banca</span>
          </label>
          <label className="flex items-center gap-2 text-sm">
            <input type="radio" name="bk-kind" checked={kind === 'to_player'} disabled={busy || creditors.length === 0} onChange={() => setKind('to_player')} />
            <span>Bancarrota por impago a otro jugador</span>
          </label>
        </fieldset>

        {kind === 'to_player' && (
          <label className="mt-2 flex flex-col gap-1 text-sm">
            <span className="text-slate-300">Acreedor</span>
            <select value={creditor} disabled={busy} onChange={(e) => setCreditor(e.target.value)} className="min-h-[40px] rounded-lg border border-slate-600 bg-slate-800 px-2 text-sm">
              <option value="">Elige un jugador…</option>
              {creditors.map((c) => <option key={c.public_ref} value={c.public_ref}>{c.display_name}</option>)}
            </select>
          </label>
        )}

        <label className="mt-2 flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Motivo</span>
          <textarea value={reason} disabled={busy} maxLength={500} onChange={(e) => setReason(e.target.value)}
            className="min-h-[60px] rounded-lg border border-slate-600 bg-slate-800 px-2 py-1 text-sm" placeholder="Explica brevemente el motivo" />
        </label>

        <div className="mt-4 flex gap-2">
          <button ref={cancelRef} type="button" onClick={onCancel} disabled={busy}
            className="min-h-[44px] flex-1 rounded-xl border border-slate-600 px-4 text-sm font-semibold disabled:opacity-40">Cancelar</button>
          <button type="button" disabled={busy || !valid}
            onClick={() => onConfirm(kind, kind === 'to_player' ? creditor : null, reason.trim())}
            className="min-h-[44px] flex-1 rounded-xl bg-rose-600 px-4 text-sm font-semibold disabled:opacity-40">
            {busy ? 'Procesando…' : 'Declararme en bancarrota'}
          </button>
        </div>
      </div>
    </div>
  );
}
