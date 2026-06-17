/** Mensaje de error de una acción del anfitrión (sin detalles internos). */
export function HostActionError({ message }: { message: string | null }) {
  if (!message) return null;
  return (
    <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
      {message}
    </p>
  );
}
