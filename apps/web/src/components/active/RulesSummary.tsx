import type { ActiveConfig } from '../../lib/activeSnapshot';
import { formatMoney } from '../../lib/activeSelectors';

const DICE_LABEL: Record<ActiveConfig['dice_mode'], string> = {
  virtual_only: 'Solo dados virtuales',
  physical_allowed: 'Dados físicos o virtuales',
  physical_only: 'Solo dados físicos',
};

function Row({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex items-start justify-between gap-3 py-0.5">
      <span className="text-slate-400">{label}</span>
      <span className="text-right text-slate-200">{value}</span>
    </div>
  );
}

const yesNo = (b: boolean) => (b ? 'Sí' : 'No');

/** Recordatorio plegable de las reglas/opciones configuradas en la partida (ayuda rápida en juego). */
export function RulesSummary({ config }: { config: ActiveConfig }) {
  return (
    <details className="rounded-xl border border-slate-700 p-3 text-xs">
      <summary className="cursor-pointer text-sm font-semibold text-slate-300">Reglas de la partida</summary>
      <div className="mt-2 flex flex-col">
        <Row label="Dinero inicial" value={formatMoney(config.initial_money)} />
        <Row label="Sueldo al pasar por la Salida" value={formatMoney(config.start_bonus)} />
        <Row label="Dados" value={DICE_LABEL[config.dice_mode]} />
        <Row label="Parking gratuito" value={config.parking_mode === 'roulette' ? 'Ruleta de evento' : 'Cobrar el bote'} />
        <Row label="Casas / hoteles disponibles" value={`${config.initial_houses_available} / ${config.initial_hotels_available}`} />
        <Row label="Construir sin el grupo completo" value={yesNo(config.allow_build_without_monopoly)} />
        <Row label="Tratos con propiedades construidas" value={yesNo(config.allow_trade_built_properties)} />
        <Row label="Incorporaciones tardías" value={yesNo(config.allow_late_join)} />
      </div>
      <p className="mt-2 text-[11px] text-slate-500">
        Los acuerdos personales de los tratos se registran pero se cumplen a mano. Algunas cartas se resuelven
        manualmente cuando su efecto no está automatizado.
      </p>
    </details>
  );
}
