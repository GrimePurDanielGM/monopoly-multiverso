import { useState } from 'react';
import type { ActiveSnapshot, BoardKey } from '../../lib/activeSnapshot';
import { parseAmount, parseBalance, isValidReason, ringSize, BOARD_LABEL } from '../../lib/activeSelectors';

/** Correcciones del anfitrión (auditadas, motivo obligatorio): ajustar saldo, fijar turno,
 *  transferir en nombre de otro jugador y corregir posición (tablero + casilla). */
export function HostCorrections({
  snap,
  busy,
  onAdjust,
  onSetTurn,
  onHostTransfer,
  onSetPosition,
}: {
  snap: ActiveSnapshot;
  busy: boolean;
  onAdjust: (targetRef: string, newBalance: number, reason: string) => void;
  onSetTurn: (targetRef: string, reason: string) => void;
  onHostTransfer: (fromRef: string, toRef: string, amount: number, reason: string) => void;
  onSetPosition: (playerRef: string, board: BoardKey, index: number, reason: string) => void;
}) {
  const refs = snap.players;
  // Corregir posición
  const [pRef, setPRef] = useState(refs[0]?.public_ref ?? '');
  const [pBoard, setPBoard] = useState<BoardKey>('classic');
  const [pIndex, setPIndex] = useState(0);
  const [pReason, setPReason] = useState('');
  const pMax = ringSize(snap, pBoard) - 1;
  const pOk = !!pRef && pIndex >= 0 && pIndex <= pMax && isValidReason(pReason) && !busy;
  // Ajuste de saldo
  const [aRef, setARef] = useState(refs[0]?.public_ref ?? '');
  const [aBal, setABal] = useState('');
  const [aReason, setAReason] = useState('');
  const aBalP = parseBalance(aBal);
  const aOk = !!aRef && aBalP.ok && isValidReason(aReason) && !busy;
  // Fijar turno
  const [tRef, setTRef] = useState(refs[0]?.public_ref ?? '');
  const [tReason, setTReason] = useState('');
  const tOk = !!tRef && isValidReason(tReason) && !busy;
  // Transferencia en nombre de otro
  const [hFrom, setHFrom] = useState(refs[0]?.public_ref ?? '');
  const [hTo, setHTo] = useState(refs[1]?.public_ref ?? '');
  const [hAmt, setHAmt] = useState('');
  const [hReason, setHReason] = useState('');
  const hAmtP = parseAmount(hAmt);
  const hOk = !!hFrom && !!hTo && hFrom !== hTo && hAmtP.ok && isValidReason(hReason) && !busy;

  const sel = (value: string, set: (v: string) => void, label: string) => (
    <label className="flex flex-col gap-1 text-sm">
      <span className="text-slate-400">{label}</span>
      <select aria-label={label} value={value} onChange={(e) => set(e.target.value)} className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base">
        {refs.map((p) => (<option key={p.public_ref} value={p.public_ref}>{p.display_name}</option>))}
      </select>
    </label>
  );
  const reasonInput = (value: string, set: (v: string) => void) => (
    <label className="flex flex-col gap-1 text-sm">
      <span className="text-slate-400">Motivo (obligatorio)</span>
      <input value={value} onChange={(e) => set(e.target.value)} maxLength={500} autoComplete="off"
        placeholder="Por qué haces esta corrección" className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
    </label>
  );

  return (
    <details className="rounded-xl border border-amber-500/30 p-4">
      <summary className="cursor-pointer text-sm font-bold text-amber-300">Correcciones del anfitrión</summary>

      <form className="mt-3 flex flex-col gap-2 border-t border-slate-800 pt-3"
        onSubmit={(e) => { e.preventDefault(); if (aOk && aBalP.ok) onAdjust(aRef, aBalP.value, aReason.trim()); }}>
        <p className="text-sm font-medium text-slate-300">Ajustar saldo</p>
        {sel(aRef, setARef, 'Jugador')}
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-400">Nuevo saldo</span>
          <input value={aBal} onChange={(e) => setABal(e.target.value)} inputMode="numeric" autoComplete="off" placeholder="0"
            className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
        </label>
        {aBal.trim() !== '' && !aBalP.ok && <p className="text-xs text-amber-300">{aBalP.reason}</p>}
        {reasonInput(aReason, setAReason)}
        <button type="submit" disabled={!aOk} className="min-h-[44px] rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40">
          {busy ? 'Aplicando…' : 'Ajustar saldo'}
        </button>
      </form>

      <form className="mt-4 flex flex-col gap-2 border-t border-slate-800 pt-3"
        onSubmit={(e) => { e.preventDefault(); if (tOk) onSetTurn(tRef, tReason.trim()); }}>
        <p className="text-sm font-medium text-slate-300">Fijar turno</p>
        {sel(tRef, setTRef, 'Jugador en turno')}
        {reasonInput(tReason, setTReason)}
        <button type="submit" disabled={!tOk} className="min-h-[44px] rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40">
          {busy ? 'Aplicando…' : 'Fijar turno'}
        </button>
      </form>

      <form className="mt-4 flex flex-col gap-2 border-t border-slate-800 pt-3"
        onSubmit={(e) => { e.preventDefault(); if (hOk && hAmtP.ok) onHostTransfer(hFrom, hTo, hAmtP.value, hReason.trim()); }}>
        <p className="text-sm font-medium text-slate-300">Transferir en nombre de un jugador</p>
        {sel(hFrom, setHFrom, 'Desde')}
        {sel(hTo, setHTo, 'Hacia')}
        {hFrom === hTo && <p className="text-xs text-amber-300">Elige jugadores distintos.</p>}
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-400">Importe</span>
          <input value={hAmt} onChange={(e) => setHAmt(e.target.value)} inputMode="numeric" autoComplete="off" placeholder="0"
            className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
        </label>
        {hAmt.trim() !== '' && !hAmtP.ok && <p className="text-xs text-amber-300">{hAmtP.reason}</p>}
        {reasonInput(hReason, setHReason)}
        <button type="submit" disabled={!hOk} className="min-h-[44px] rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40">
          {busy ? 'Aplicando…' : 'Transferir (corrección)'}
        </button>
      </form>

      <form className="mt-4 flex flex-col gap-2 border-t border-slate-800 pt-3"
        onSubmit={(e) => { e.preventDefault(); if (pOk) onSetPosition(pRef, pBoard, pIndex, pReason.trim()); }}>
        <p className="text-sm font-medium text-slate-300">Corregir posición de jugador</p>
        <p className="text-xs text-slate-500">No cobra salida, no compra ni paga alquiler y no avanza turno; solo coloca la ficha.</p>
        {sel(pRef, setPRef, 'Jugador')}
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-400">Tablero</span>
          <select aria-label="Tablero" value={pBoard} onChange={(e) => { setPBoard(e.target.value as BoardKey); setPIndex(0); }}
            className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base">
            <option value="classic">{BOARD_LABEL.classic}</option>
            <option value="back_to_the_future">{BOARD_LABEL.back_to_the_future}</option>
          </select>
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-400">Casilla (0–{pMax})</span>
          <input value={pIndex} onChange={(e) => setPIndex(Math.max(0, Math.min(pMax, Number(e.target.value) || 0)))}
            inputMode="numeric" type="number" min={0} max={pMax}
            className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
        </label>
        {reasonInput(pReason, setPReason)}
        <button type="submit" disabled={!pOk} className="min-h-[44px] rounded-xl bg-amber-600 px-4 text-sm font-semibold disabled:opacity-40">
          {busy ? 'Aplicando…' : 'Actualizar posición'}
        </button>
      </form>
    </details>
  );
}
