import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import { promises as fsp } from 'node:fs';
import {
  UploadStore,
  claveValida,
  generarClaveBorrado,
  hashClave,
  hashContenido,
  safeExt,
  sanitizeName,
} from '../lib/store.mjs';

async function storeTemporal() {
  const dir = await fsp.mkdtemp(path.join(os.tmpdir(), 'album-test-'));
  const store = new UploadStore(dir);
  await store.init();
  return { dir, store };
}

test('extensiones seguras según nombre o tipo MIME', () => {
  assert.equal(safeExt('playa.JPG', 'image/jpeg'), '.jpg');
  assert.equal(safeExt('foto.jpeg', 'image/jpeg'), '.jpg');
  assert.equal(safeExt('sin-extension', 'image/png'), '.png');
  assert.equal(safeExt('raro.exe', 'video/mp4'), '.mp4');
  assert.equal(safeExt('raro.exe', 'application/x-msdownload'), '.bin');
});

test('sanea nombres de archivo', () => {
  assert.equal(sanitizeName('../../etc/passwd'), '.. .. etc passwd');
  assert.ok(!sanitizeName('foto<script>.jpg').includes('<'));
});

test('añade, lista, cambia de estado y borra subidas', async () => {
  const { dir, store } = await storeTemporal();
  const { item, clave } = await store.add({
    data: Buffer.from('imagen-falsa'),
    filename: 'playa.jpg',
    contentType: 'image/jpeg',
    uploader: 'María',
    caption: 'Qué calor',
  });
  assert.equal(item.estado, 'pendiente');
  assert.equal(item.uploader, 'María');
  assert.ok(item.storedName.endsWith('.jpg'));

  // clave de borrado: la de verdad valida, otra no; solo se guarda su hash
  assert.match(clave, /^[0-9a-f]{32}$/);
  assert.equal(item.claveBorradoHash, hashClave(clave));
  assert.ok(claveValida(clave, item.claveBorradoHash));
  assert.ok(!claveValida('otra-clave', item.claveBorradoHash));
  assert.ok(!claveValida('', item.claveBorradoHash));

  // huella del contenido para detectar duplicados
  assert.equal(item.hash, hashContenido(Buffer.from('imagen-falsa')));
  assert.equal(store.findByHash(item.hash), item);
  assert.equal(store.findByHash('no-existe'), null);

  // el archivo existe de verdad
  const contenido = await fsp.readFile(path.join(dir, 'uploads', item.storedName), 'utf8');
  assert.equal(contenido, 'imagen-falsa');

  // se recarga desde disco
  const store2 = new UploadStore(dir);
  await store2.init();
  assert.equal(store2.list().length, 1);

  await store2.setEstado(item.id, 'en_icloud');
  assert.equal(store2.get(item.id).estado, 'en_icloud');

  assert.equal(await store2.remove(item.id), true);
  assert.equal(store2.list().length, 0);
  await assert.rejects(fsp.stat(path.join(dir, 'uploads', item.storedName)));
});

test('claves de borrado distintas en cada subida', () => {
  assert.notEqual(generarClaveBorrado(), generarClaveBorrado());
});

test('filePath rechaza rutas peligrosas o desconocidas', async () => {
  const { store } = await storeTemporal();
  const { item } = await store.add({
    data: Buffer.from('x'),
    filename: 'a.png',
    contentType: 'image/png',
    uploader: 'Ana',
    caption: '',
  });
  assert.ok(store.filePath(item.storedName));
  assert.equal(store.filePath('../uploads.json'), null);
  assert.equal(store.filePath('no-existe.png'), null);
  assert.equal(store.filePath('.oculto'), null);
});
