import test from 'node:test';
import assert from 'node:assert/strict';
import { boundaryFromContentType, parseMultipart } from '../lib/multipart.mjs';

const B = '----WebKitFormBoundaryabc123';

function cuerpo(partes) {
  const trozos = [];
  for (const p of partes) {
    trozos.push(Buffer.from(`--${B}\r\n`));
    trozos.push(Buffer.from(p.cabeceras.join('\r\n') + '\r\n\r\n'));
    trozos.push(Buffer.isBuffer(p.contenido) ? p.contenido : Buffer.from(p.contenido));
    trozos.push(Buffer.from('\r\n'));
  }
  trozos.push(Buffer.from(`--${B}--\r\n`));
  return Buffer.concat(trozos);
}

test('extrae el boundary del content-type', () => {
  assert.equal(boundaryFromContentType(`multipart/form-data; boundary=${B}`), B);
  assert.equal(boundaryFromContentType(`multipart/form-data; boundary="${B}"`), B);
  assert.equal(boundaryFromContentType('application/json'), null);
});

test('analiza campos de texto y archivos binarios', () => {
  // bytes conflictivos: nulos, 0xFF, saltos de línea y "--" dentro del contenido
  const binario = Buffer.concat([
    Buffer.from([0xff, 0xd8, 0x00, 0x0d, 0x0a]),
    Buffer.from('--no-soy-el-delimitador\r\n'),
    Buffer.from([0x2d, 0x2d, 0x00, 0xfe, 0x01]),
  ]);
  const body = cuerpo([
    { cabeceras: ['Content-Disposition: form-data; name="nombre"'], contenido: 'María ñoño' },
    { cabeceras: ['Content-Disposition: form-data; name="comentario"'], contenido: '' },
    {
      cabeceras: [
        'Content-Disposition: form-data; name="fotos"; filename="playa día 1.jpg"',
        'Content-Type: image/jpeg',
      ],
      contenido: binario,
    },
    {
      cabeceras: [
        'Content-Disposition: form-data; name="fotos"; filename="video.mp4"',
        'Content-Type: video/mp4',
      ],
      contenido: Buffer.from('ftypmp42'),
    },
  ]);

  const { fields, files } = parseMultipart(body, B);
  assert.equal(fields.nombre, 'María ñoño');
  assert.equal(fields.comentario, '');
  assert.equal(files.length, 2);
  assert.equal(files[0].field, 'fotos');
  assert.equal(files[0].filename, 'playa día 1.jpg');
  assert.equal(files[0].contentType, 'image/jpeg');
  assert.ok(files[0].data.equals(binario), 'el binario debe llegar byte a byte');
  assert.equal(files[1].contentType, 'video/mp4');
  assert.equal(files[1].data.toString(), 'ftypmp42');
});

test('archivo vacío y cuerpo sin delimitador', () => {
  const body = cuerpo([
    {
      cabeceras: ['Content-Disposition: form-data; name="fotos"; filename="vacia.jpg"', 'Content-Type: image/jpeg'],
      contenido: Buffer.alloc(0),
    },
  ]);
  const { files } = parseMultipart(body, B);
  assert.equal(files.length, 1);
  assert.equal(files[0].data.length, 0);

  assert.throws(() => parseMultipart(Buffer.from('nada que ver'), B));
});
