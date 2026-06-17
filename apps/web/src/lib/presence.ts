// Presence efímera y declarada por el cliente: SOLO transporta { public_ref }.
// Se ignora cualquier public_ref vacío, con formato inválido o que no exista en el snapshot.
export const PUBLIC_REF_RE = /^P-[0-9A-F]{10}$/;

interface PresenceEntry {
  public_ref?: unknown;
}
type RawPresenceState = Record<string, PresenceEntry[] | undefined>;

/** Extrae los public_ref declarados en el presenceState crudo de Supabase (sin filtrar todavía). */
export function presenceRefsFromState(state: RawPresenceState): string[] {
  const refs: string[] = [];
  for (const entries of Object.values(state)) {
    for (const e of entries ?? []) {
      if (typeof e.public_ref === 'string') refs.push(e.public_ref);
    }
  }
  return refs;
}

/** Filtra a los public_ref válidos (formato correcto) Y presentes en el snapshot. Únicos. */
export function filterPresentRefs(rawRefs: Iterable<string>, knownRefs: ReadonlySet<string>): string[] {
  const out = new Set<string>();
  for (const r of rawRefs) {
    if (typeof r !== 'string' || r.length === 0) continue;
    if (!PUBLIC_REF_RE.test(r)) continue;
    if (!knownRefs.has(r)) continue;
    out.add(r);
  }
  return [...out];
}
