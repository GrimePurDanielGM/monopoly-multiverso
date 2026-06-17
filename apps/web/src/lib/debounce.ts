// Debounce trailing: agrupa llamadas consecutivas y ejecuta una sola vez tras `ms`
// de calma, SIN perder la última invocación. cancel() limpia el temporizador pendiente.
export interface Debouncer {
  call: () => void;
  cancel: () => void;
}

export function createDebouncer(fn: () => void, ms: number): Debouncer {
  let timer: ReturnType<typeof setTimeout> | undefined;
  return {
    call() {
      if (timer !== undefined) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = undefined;
        fn();
      }, ms);
    },
    cancel() {
      if (timer !== undefined) {
        clearTimeout(timer);
        timer = undefined;
      }
    },
  };
}
