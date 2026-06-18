import { useState } from 'react';
import type { FormEvent } from 'react';
import { configErrors } from '../lib/hostConfig';

export interface ConfigPatch {
  name: string;
  min_players: number;
  max_players: number;
  initial_money: number;
  allow_late_join: boolean;
}

interface Props {
  name: string;
  minPlayers: number;
  maxPlayers: number;
  initialMoney: number;
  allowLateJoin: boolean;
  currentPlayers: number;
  busy: boolean;
  onSubmit: (patch: ConfigPatch) => void;
}

const numField = (v: string, fallback: number): number => {
  const n = parseInt(v, 10);
  return Number.isNaN(n) ? fallback : n;
};

/** Edición de la configuración del lobby (solo whitelist de update_config). */
export function GameConfigForm({ name, minPlayers, maxPlayers, initialMoney, allowLateJoin, currentPlayers, busy, onSubmit }: Props) {
  const [n, setN] = useState(name);
  const [min, setMin] = useState(minPlayers);
  const [max, setMax] = useState(maxPlayers);
  const [money, setMoney] = useState(initialMoney);
  const [late, setLate] = useState(allowLateJoin);

  const errs = configErrors({ name: n, minPlayers: min, maxPlayers: max, initialMoney: money }, currentPlayers);
  const valid = errs.length === 0;

  function submit(e: FormEvent) {
    e.preventDefault();
    if (!valid || busy) return;
    onSubmit({ name: n.trim(), min_players: min, max_players: max, initial_money: money, allow_late_join: late });
  }

  return (
    <form className="flex flex-col gap-3" onSubmit={submit} noValidate>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-300">Nombre de la partida</span>
        <input value={n} onChange={(e) => setN(e.target.value)} maxLength={40} className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
      </label>
      <div className="grid grid-cols-2 gap-2">
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Mínimo</span>
          <input type="number" inputMode="numeric" min={2} max={16} value={min} onChange={(e) => setMin(numField(e.target.value, min))} className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
        </label>
        <label className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Máximo</span>
          <input type="number" inputMode="numeric" min={2} max={16} value={max} onChange={(e) => setMax(numField(e.target.value, max))} className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
        </label>
      </div>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-300">Dinero inicial</span>
        <input type="number" inputMode="numeric" min={1} value={money} onChange={(e) => setMoney(numField(e.target.value, money))} className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
      </label>

      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" checked={late} onChange={(e) => setLate(e.target.checked)} className="mt-1 h-4 w-4" />
        <span className="flex flex-col">
          <span className="text-slate-200">Permitir que entren jugadores después de iniciar</span>
          <span className="text-xs text-slate-500">
            Las nuevas incorporaciones necesitarán aprobación del anfitrión y entrarán con el saldo inicial, sin propiedades ni compensaciones.
          </span>
        </span>
      </label>

      {!valid && (
        <ul className="list-inside list-disc text-xs text-amber-300">
          {errs.map((m) => (
            <li key={m}>{m}</li>
          ))}
        </ul>
      )}

      <button type="submit" disabled={!valid || busy} className="min-h-[44px] rounded-xl bg-indigo-600 px-4 text-sm font-semibold disabled:opacity-40">
        {busy ? 'Guardando…' : 'Guardar configuración'}
      </button>
    </form>
  );
}
