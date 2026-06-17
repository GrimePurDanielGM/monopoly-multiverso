// Compartir/copiar el enlace de unión. Web Share API cuando existe; si no, portapapeles.
// El enlace SOLO contiene la URL pública /j/{CODE} (nunca JWT, PIN, ids internos ni secretos).
export type ShareMethod = 'share' | 'clipboard' | 'none';

function canShare(): boolean {
  return typeof navigator !== 'undefined' && typeof (navigator as Navigator).share === 'function';
}

export async function copyToClipboard(text: string): Promise<boolean> {
  try {
    await navigator.clipboard.writeText(text);
    return true;
  } catch {
    return false;
  }
}

export async function shareOrCopy(data: { title: string; text: string; url: string }): Promise<ShareMethod> {
  if (canShare()) {
    try {
      await navigator.share(data);
    } catch {
      /* el usuario canceló o falló: no copiamos detrás */
    }
    return 'share';
  }
  const ok = await copyToClipboard(data.url);
  return ok ? 'clipboard' : 'none';
}
