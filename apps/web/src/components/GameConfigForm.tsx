import { useState } from 'react';
import type { FormEvent } from 'react';
import { configErrors } from '../lib/hostConfig';
import { NumberStepper } from './NumberStepper';

export type DiceModeOption = 'virtual_only' | 'physical_allowed' | 'physical_only';

export interface ConfigPatch {
  name: string;
  min_players: number;
  max_players: number;
  initial_money: number;
  allow_late_join: boolean;
  dice_mode: DiceModeOption;
  initial_houses_available: number;
  initial_hotels_available: number;
  allow_build_without_monopoly: boolean;
  allow_trade_built_properties: boolean;
  parking_mode: 'pot' | 'roulette';
}

interface Props {
  name: string;
  minPlayers: number;
  maxPlayers: number;
  initialMoney: number;
  allowLateJoin: boolean;
  diceMode: DiceModeOption;
  housesAvailable: number;
  hotelsAvailable: number;
  allowBuildWithoutMonopoly: boolean;
  allowTradeBuiltProperties: boolean;
  parkingMode: 'pot' | 'roulette';
  currentPlayers: number;
  busy: boolean;
  onSubmit: (patch: ConfigPatch) => void;
}

/** Edición de la configuración del lobby (solo whitelist de update_config). */
export function GameConfigForm({ name, minPlayers, maxPlayers, initialMoney, allowLateJoin, diceMode, housesAvailable, hotelsAvailable, allowBuildWithoutMonopoly, allowTradeBuiltProperties, parkingMode, currentPlayers, busy, onSubmit }: Props) {
  const [n, setN] = useState(name);
  const [min, setMin] = useState(minPlayers);
  const [max, setMax] = useState(maxPlayers);
  const [money, setMoney] = useState(initialMoney);
  const [late, setLate] = useState(allowLateJoin);
  const [dice, setDice] = useState<DiceModeOption>(diceMode);
  const [houses, setHouses] = useState(housesAvailable);
  const [hotels, setHotels] = useState(hotelsAvailable);
  const [noMono, setNoMono] = useState(allowBuildWithoutMonopoly);
  const [tradeBuilt, setTradeBuilt] = useState(allowTradeBuiltProperties);
  const [parking, setParking] = useState<'pot' | 'roulette'>(parkingMode);

  const stockErr = houses < 32 || hotels < 12 ? 'El mínimo son 32 casas y 12 hoteles.' : null;
  const errs = configErrors({ name: n, minPlayers: min, maxPlayers: max, initialMoney: money }, currentPlayers);
  const valid = errs.length === 0 && !stockErr;

  function submit(e: FormEvent) {
    e.preventDefault();
    if (!valid || busy) return;
    onSubmit({ name: n.trim(), min_players: min, max_players: max, initial_money: money, allow_late_join: late, dice_mode: dice,
      initial_houses_available: houses, initial_hotels_available: hotels, allow_build_without_monopoly: noMono, allow_trade_built_properties: tradeBuilt, parking_mode: parking });
  }

  return (
    <form className="flex flex-col gap-3" onSubmit={submit} noValidate>
      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-300">Nombre de la partida</span>
        <input value={n} onChange={(e) => setN(e.target.value)} maxLength={40} className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
      </label>
      <div className="grid grid-cols-2 gap-2">
        <div className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Mínimo</span>
          <NumberStepper ariaLabel="Mínimo" value={min} onChange={setMin} min={2} max={16} />
        </div>
        <div className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Máximo</span>
          <NumberStepper ariaLabel="Máximo" value={max} onChange={setMax} min={2} max={16} />
        </div>
      </div>
      <div className="flex flex-col gap-1 text-sm">
        <span className="text-slate-300">Dinero inicial</span>
        <NumberStepper ariaLabel="Dinero inicial" value={money} onChange={setMoney} min={1} step={100} />
      </div>

      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-300">Configuración de dados</span>
        <select aria-label="Configuración de dados" value={dice} onChange={(e) => setDice(e.target.value as DiceModeOption)}
          className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base">
          <option value="virtual_only">Solo dados virtuales</option>
          <option value="physical_allowed">Permitir dados físicos y virtuales</option>
          <option value="physical_only">Solo dados físicos</option>
        </select>
      </label>

      <label className="flex flex-col gap-1 text-sm">
        <span className="text-slate-300">Parking gratuito</span>
        <select aria-label="Parking gratuito" value={parking} onChange={(e) => setParking(e.target.value as 'pot' | 'roulette')}
          className="min-h-[44px] rounded-lg border border-slate-600 bg-slate-800 px-3 text-base">
          <option value="pot">Cobrar el bote acumulado</option>
          <option value="roulette">Ruleta de evento (incluye el bote)</option>
        </select>
        <span className="text-xs text-slate-500">
          Con «ruleta», al caer en Parking se gira una ruleta de 7 resultados (cobrar el bote ×2, robar carta, ir a la
          cárcel, perder tu propiedad más/menos valiosa, o pagar 500 € al bote). El bote tiene un tope de 2.500 €.
        </span>
      </label>

      <div className="grid grid-cols-2 gap-2">
        <div className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Casas disponibles</span>
          <NumberStepper ariaLabel="Casas disponibles" value={houses} onChange={setHouses} min={32} />
        </div>
        <div className="flex flex-col gap-1 text-sm">
          <span className="text-slate-300">Hoteles disponibles</span>
          <NumberStepper ariaLabel="Hoteles disponibles" value={hotels} onChange={setHotels} min={12} />
        </div>
      </div>
      <p className="text-xs text-slate-500">El mínimo son 32 casas y 12 hoteles. Puedes aumentar el stock si la partida usa dos tableros.</p>
      {stockErr && <p className="text-xs text-amber-300">{stockErr}</p>}

      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" checked={noMono} onChange={(e) => setNoMono(e.target.checked)} className="mt-1 h-4 w-4" />
        <span className="flex flex-col">
          <span className="text-slate-200">Permitir construir casas sin tener el grupo completo</span>
          <span className="text-xs text-slate-500">
            Si está activado, cada jugador puede construir en propiedades suyas aunque no tenga todo el grupo de color. El grupo completo sigue dando alquiler doble si no hay construcciones.
          </span>
        </span>
      </label>

      <label className="flex items-start gap-2 text-sm">
        <input type="checkbox" checked={tradeBuilt} onChange={(e) => setTradeBuilt(e.target.checked)} className="mt-1 h-4 w-4" />
        <span className="flex flex-col">
          <span className="text-slate-200">Permitir tratos con propiedades construidas</span>
          <span className="text-xs text-slate-500">
            Si se activa, una propiedad con casas u hotel puede venderse o intercambiarse. El nuevo propietario recibe también esas construcciones.
          </span>
        </span>
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
