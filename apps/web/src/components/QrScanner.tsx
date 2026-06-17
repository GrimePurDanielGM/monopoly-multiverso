import { useCallback, useEffect, useRef, useState } from 'react';
import { BrowserMultiFormatReader } from '@zxing/browser';
import type { IScannerControls } from '@zxing/browser';
import { parseScannedCode } from '../lib/qr';
import { PUBLIC_BASE_URL } from '../lib/config';
import { isValidCode, normalizeCode } from '../lib/codes';

type ScanError = 'denied' | 'no-camera' | null;

interface BarcodeDetectorLike {
  detect(source: HTMLVideoElement): Promise<{ rawValue: string }[]>;
}
interface BarcodeDetectorCtor {
  new (opts: { formats: string[] }): BarcodeDetectorLike;
}

/** Escáner QR modal. La cámara se pide SOLO tras pulsar; se libera siempre (detección,
 *  cancelar, cerrar, desmontar, segundo plano). Fallback manual permanente (código/enlace). */
export function QrScanner({ open, onDetected, onClose }: { open: boolean; onDetected: (code: string) => void; onClose: () => void }) {
  const videoRef = useRef<HTMLVideoElement>(null);
  const streamRef = useRef<MediaStream | null>(null);
  const rafRef = useRef<number | undefined>(undefined);
  const zxingRef = useRef<IScannerControls | null>(null);
  const [scanning, setScanning] = useState(false);
  const [error, setError] = useState<ScanError>(null);
  const [invalid, setInvalid] = useState(false);
  const [manual, setManual] = useState('');

  const stopCamera = useCallback(() => {
    if (rafRef.current !== undefined) {
      cancelAnimationFrame(rafRef.current);
      rafRef.current = undefined;
    }
    if (zxingRef.current) {
      zxingRef.current.stop();
      zxingRef.current = null;
    }
    if (streamRef.current) {
      for (const t of streamRef.current.getTracks()) t.stop();
      streamRef.current = null;
    }
    if (videoRef.current) videoRef.current.srcObject = null;
    setScanning(false);
  }, []);

  const accept = useCallback(
    (text: string) => {
      const code = parseScannedCode(text, PUBLIC_BASE_URL);
      if (code) {
        stopCamera();
        onDetected(code);
      } else {
        setInvalid(true); // QR de otra app: seguimos
      }
    },
    [onDetected, stopCamera],
  );

  const startCamera = useCallback(async () => {
    setError(null);
    setInvalid(false);
    if (typeof navigator === 'undefined' || !navigator.mediaDevices?.getUserMedia) {
      setError('no-camera');
      return;
    }
    let stream: MediaStream;
    try {
      stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } });
    } catch (e) {
      setError(e instanceof DOMException && e.name === 'NotAllowedError' ? 'denied' : 'no-camera');
      return;
    }
    streamRef.current = stream;
    const video = videoRef.current;
    if (video) {
      video.srcObject = stream;
      try {
        await video.play();
      } catch {
        /* autoplay/jsdom: ignorar */
      }
    }
    setScanning(true);

    const Detector = (globalThis as { BarcodeDetector?: BarcodeDetectorCtor }).BarcodeDetector;
    if (Detector && video) {
      const det = new Detector({ formats: ['qr_code'] });
      const loop = async () => {
        if (!streamRef.current || !videoRef.current) return;
        try {
          const found = await det.detect(videoRef.current);
          const raw = found[0]?.rawValue;
          if (raw) {
            accept(raw);
            return;
          }
        } catch {
          /* fotograma no legible */
        }
        rafRef.current = requestAnimationFrame(() => void loop());
      };
      rafRef.current = requestAnimationFrame(() => void loop());
    } else if (video) {
      const reader = new BrowserMultiFormatReader();
      zxingRef.current = await reader.decodeFromStream(stream, video, (result) => {
        if (result) accept(result.getText());
      });
    }
  }, [accept]);

  useEffect(() => {
    if (!open) stopCamera();
    return () => stopCamera();
  }, [open, stopCamera]);

  useEffect(() => {
    const onVis = () => {
      if (document.visibilityState !== 'visible') stopCamera();
    };
    document.addEventListener('visibilitychange', onVis);
    return () => document.removeEventListener('visibilitychange', onVis);
  }, [stopCamera]);

  if (!open) return null;

  const submitManual = () => {
    const c = normalizeCode(manual);
    if (isValidCode(c)) {
      stopCamera();
      onDetected(c);
    } else {
      accept(manual); // por si pegaron un enlace completo
    }
  };

  return (
    <div role="dialog" aria-modal="true" aria-label="Escanear QR" className="fixed inset-0 z-50 flex flex-col bg-slate-950 p-4 pt-[max(1rem,env(safe-area-inset-top))]">
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-bold">Escanear QR</h2>
        <button type="button" onClick={() => { stopCamera(); onClose(); }} className="min-h-[44px] rounded-lg px-3 text-sm">
          Cerrar
        </button>
      </div>

      <div className="mt-3 flex-1">
        {!scanning && !error && (
          <button type="button" onClick={() => void startCamera()} className="w-full rounded-xl bg-indigo-600 px-4 py-3 font-semibold">
            Escanear QR
          </button>
        )}
        {error && (
          <p role="alert" className="rounded-lg bg-rose-950/60 px-3 py-2 text-sm text-rose-200">
            {error === 'denied' ? 'Permiso de cámara denegado. Usa el código o el enlace.' : 'Cámara no disponible. Usa el código o el enlace.'}
          </p>
        )}
        <video ref={videoRef} className={`mt-3 w-full rounded-xl ${scanning ? '' : 'hidden'}`} muted playsInline aria-label="Vista de la cámara" />
        {invalid && <p role="alert" className="mt-2 text-sm text-amber-300">Ese QR no es de una sala válida.</p>}
      </div>

      <div className="mt-3 flex flex-col gap-2 border-t border-slate-800 pt-3">
        <label htmlFor="qr-manual" className="text-sm text-slate-300">
          O introduce el código o pega el enlace
        </label>
        <div className="flex gap-2">
          <input id="qr-manual" value={manual} onChange={(e) => setManual(e.target.value)} className="min-h-[44px] flex-1 rounded-lg border border-slate-600 bg-slate-800 px-3 text-base" />
          <button type="button" onClick={submitManual} className="min-h-[44px] rounded-lg bg-indigo-600 px-4 font-semibold">
            Usar
          </button>
        </div>
      </div>
    </div>
  );
}
