import { useEffect, useState } from 'react';

/** Campo numérico con botones [−] [valor editable] [+], cómodo en iPhone.
 *  Permite escribir a mano y dejar estados temporales incompletos (vacío): NO bloquea mientras se escribe;
 *  la validación de mínimo/máximo se hace al guardar (en el formulario). Los botones +/− sí respetan min/max. */
export function NumberStepper({
  value, onChange, min, max, step = 1, ariaLabel, disabled = false,
}: {
  value: number;
  onChange: (n: number) => void;
  min?: number;
  max?: number;
  step?: number;
  ariaLabel: string;
  disabled?: boolean;
}) {
  const [text, setText] = useState(String(value));
  // Sincroniza el texto cuando el valor cambia desde fuera (p. ej. los botones +/−), sin pisar lo que se escribe.
  useEffect(() => { setText(String(value)); }, [value]);

  const commit = (raw: string) => {
    setText(raw);
    const n = parseInt(raw, 10);
    if (!Number.isNaN(n)) onChange(n); // vacío/incompleto → no propaga: el formulario conserva el último válido
  };
  const dec = () => onChange(Math.max(min ?? Number.MIN_SAFE_INTEGER, value - step));
  const inc = () => onChange(Math.min(max ?? Number.MAX_SAFE_INTEGER, value + step));

  const btn = 'flex h-11 w-11 shrink-0 items-center justify-center rounded-lg border border-slate-600 bg-slate-800 text-xl font-bold leading-none disabled:opacity-40';
  // Las etiquetas de los botones son genéricas ("Disminuir"/"Aumentar"): así el nombre del campo solo lo lleva
  // el input (evita colisiones de subcadena con getByLabel en E2E). El title da contexto en escritorio.
  return (
    <div className="flex items-stretch gap-2">
      <button type="button" aria-label="Disminuir" title={`Disminuir ${ariaLabel}`} onClick={dec} disabled={disabled || value <= (min ?? Number.MIN_SAFE_INTEGER)} className={btn}>−</button>
      <input
        type="text"
        inputMode="numeric"
        pattern="[0-9]*"
        aria-label={ariaLabel}
        min={min}
        max={max}
        value={text}
        disabled={disabled}
        onChange={(e) => commit(e.target.value)}
        onBlur={() => setText(String(value))}
        className="min-h-[44px] w-full min-w-0 rounded-lg border border-slate-600 bg-slate-800 px-3 text-center text-base tabular-nums"
      />
      <button type="button" aria-label="Aumentar" title={`Aumentar ${ariaLabel}`} onClick={inc} disabled={disabled || value >= (max ?? Number.MAX_SAFE_INTEGER)} className={btn}>+</button>
    </div>
  );
}
