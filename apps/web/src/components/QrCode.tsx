import { useEffect, useState } from 'react';
import QRCode from 'qrcode';

/** Genera el QR LOCALMENTE (no envía el enlace a ningún servicio). Texto alternativo incluido. */
export function QrCode({ url, size = 176 }: { url: string; size?: number }) {
  const [dataUrl, setDataUrl] = useState<string | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    let active = true;
    setFailed(false);
    void QRCode.toDataURL(url, {
      margin: 2,
      width: size,
      errorCorrectionLevel: 'M',
      color: { dark: '#0f172a', light: '#ffffff' }, // contraste alto
    })
      .then((d) => {
        if (active) setDataUrl(d);
      })
      .catch(() => {
        if (active) setFailed(true);
      });
    return () => {
      active = false;
    };
  }, [url, size]);

  if (failed) return <p className="text-xs text-rose-300">No se pudo generar el QR.</p>;
  if (!dataUrl) return <div style={{ width: size, height: size }} className="rounded bg-slate-700 motion-safe:animate-pulse" aria-hidden />;
  return <img src={dataUrl} width={size} height={size} alt={`Código QR del enlace de la sala: ${url}`} className="rounded bg-white p-1" />;
}
