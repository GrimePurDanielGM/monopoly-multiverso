import { useEffect } from 'react';
import type { RefObject } from 'react';

const FOCUSABLE =
  'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

interface Options {
  /** Acción al pulsar Escape (si está habilitado y el navegador no lo intercepta). */
  onEscape?: () => void;
  /** Permite cerrar con Escape. Por defecto true. */
  escapeEnabled?: boolean;
  /** Elemento a enfocar al abrir. Si no, el primer enfocable del diálogo. */
  initialFocusRef?: RefObject<HTMLElement | null>;
}

/**
 * Accesibilidad común de diálogos modales: foco inicial al abrir, *focus-trap*
 * con Tab/Shift+Tab dentro del contenedor, cierre opcional con Escape y devolución
 * del foco al elemento que tenía el foco antes de abrir. No sustituye al botón
 * visible de cerrar/cancelar: Escape es un extra, no la única vía.
 */
export function useDialogA11y(open: boolean, dialogRef: RefObject<HTMLElement | null>, options: Options = {}): void {
  const { onEscape, escapeEnabled = true, initialFocusRef } = options;

  useEffect(() => {
    if (!open) return;
    const prevFocused = document.activeElement as HTMLElement | null;

    const focusables = (): HTMLElement[] =>
      dialogRef.current ? Array.from(dialogRef.current.querySelectorAll<HTMLElement>(FOCUSABLE)) : [];

    // Foco inicial: elemento indicado, primer enfocable o el propio contenedor.
    const target = initialFocusRef?.current ?? focusables()[0] ?? dialogRef.current;
    target?.focus();

    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && escapeEnabled && onEscape) {
        onEscape();
        return;
      }
      if (e.key !== 'Tab') return;
      // Gestión COMPLETA del Tab: no dependemos del orden de tabulación nativo (en
      // WebKit/Safari sin "Full Keyboard Access" los botones no entran en él). Siempre
      // movemos el foco por la lista de enfocables del diálogo, con ciclo en ambos sentidos.
      const f = focusables();
      e.preventDefault();
      if (f.length === 0) return;
      const active = document.activeElement as HTMLElement | null;
      const idx = active ? f.indexOf(active) : -1;
      let next: number;
      if (idx === -1) next = e.shiftKey ? f.length - 1 : 0; // foco fuera -> entrar por un extremo
      else next = e.shiftKey ? (idx - 1 + f.length) % f.length : (idx + 1) % f.length;
      f[next]!.focus();
    };

    document.addEventListener('keydown', onKey);
    return () => {
      document.removeEventListener('keydown', onKey);
      prevFocused?.focus?.();
    };
  }, [open, escapeEnabled, onEscape, dialogRef, initialFocusRef]);
}
