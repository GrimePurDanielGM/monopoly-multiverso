import test from 'node:test';
import assert from 'node:assert/strict';
import os from 'node:os';
import path from 'node:path';
import { promises as fsp } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { crc32, crearZip } from '../public/zip.js';

function leerU32(buf, pos) {
  return new DataView(buf.buffer, buf.byteOffset + pos, 4).getUint32(0, true);
}

test('crc32 conocido', () => {
  // Valor de referencia estándar para la cadena "123456789"
  assert.equal(crc32(new TextEncoder().encode('123456789')), 0xcbf43926);
});

test('crearZip produce una estructura ZIP válida', async () => {
  const foto = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46]);
  const texto = new TextEncoder().encode('hola familia á é í');
  const zip = crearZip([
    { nombre: 'IMG_0001.jpg', datos: foto },
    { nombre: 'notas día 1.txt', datos: texto },
  ]);

  // firmas: cabecera local al inicio y fin de directorio central al final
  assert.equal(leerU32(zip, 0), 0x04034b50);
  assert.equal(leerU32(zip, zip.length - 22), 0x06054b50);

  // el fin de directorio declara 2 entradas y apunta a un directorio central válido
  const vista = new DataView(zip.buffer, zip.byteOffset + zip.length - 22, 22);
  assert.equal(vista.getUint16(8, true), 2);
  const iniCentral = vista.getUint32(16, true);
  assert.equal(leerU32(zip, iniCentral), 0x02014b50);

  // los bytes de la primera entrada están tal cual (STORE) tras cabecera+nombre
  const nombre1 = 'IMG_0001.jpg'.length;
  const datos1 = zip.subarray(30 + nombre1, 30 + nombre1 + foto.length);
  assert.deepEqual([...datos1], [...foto]);

  // si el sistema tiene unzip, validación de integridad completa
  try {
    const tmp = path.join(await fsp.mkdtemp(path.join(os.tmpdir(), 'zip-test-')), 'prueba.zip');
    await fsp.writeFile(tmp, zip);
    const salida = execFileSync('unzip', ['-t', tmp], { encoding: 'utf8' });
    assert.match(salida, /No errors detected/);
  } catch (err) {
    if (err.code !== 'ENOENT') throw err; // sin unzip instalado: se omite
  }
});
