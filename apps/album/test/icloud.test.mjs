import test from 'node:test';
import assert from 'node:assert/strict';
import { SharedAlbum, buildPhoto, partitionFromToken, tokenFromUrl } from '../lib/icloud.mjs';

test('extrae el token de un enlace de iCloud', () => {
  assert.equal(tokenFromUrl('https://www.icloud.com/sharedalbum/#B2PGgZLKuKkNJ1h'), 'B2PGgZLKuKkNJ1h');
  assert.equal(tokenFromUrl('https://www.icloud.com/sharedalbum/es-es/#B2PGgZLKuKkNJ1h'), 'B2PGgZLKuKkNJ1h');
  assert.equal(tokenFromUrl('B2PGgZLKuKkNJ1h'), 'B2PGgZLKuKkNJ1h');
});

test('calcula la partición del token (verificada contra iCloud real)', () => {
  // El álbum B2PG… vive en p149 según la cabecera x-apple-user-partition
  assert.equal(partitionFromToken('B2PGgZLKuKkNJ1h'), 149);
  assert.equal(partitionFromToken('A1x'), 1);
});

test('sigue la redirección 330 a la partición correcta', async () => {
  const llamadas = [];
  const fetchImpl = async (url) => {
    llamadas.push(url);
    if (llamadas.length === 1) {
      return {
        status: 330,
        ok: false,
        headers: { get: (k) => (k === 'x-apple-mme-host' ? 'p99-sharedstreams.icloud.com' : null) },
        json: async () => ({ 'X-Apple-MMe-Host': 'p99-sharedstreams.icloud.com' }),
      };
    }
    return {
      status: 200,
      ok: true,
      headers: { get: () => null },
      json: async () => ({ streamName: 'Prueba', photos: [] }),
    };
  };
  const album = new SharedAlbum('B2PGgZLKuKkNJ1h', { fetchImpl });
  const datos = await album.getStream();
  assert.equal(datos.streamName, 'Prueba');
  assert.match(llamadas[1], /^https:\/\/p99-sharedstreams\.icloud\.com\//);
  assert.equal(album.host, 'p99-sharedstreams.icloud.com');
});

const urls = new Map([
  ['sum-342', { url: 'https://cvws.icloud-content.com/342.jpg' }],
  ['sum-2049', { url: 'https://cvws.icloud-content.com/2049.jpg' }],
  ['sum-poster', { url: 'https://cvws.icloud-content.com/poster.jpg' }],
  ['sum-720p', { url: 'https://cvws.icloud-content.com/720p.mov' }],
]);
const urlFor = (ck) => urls.get(ck)?.url || null;

test('normaliza una foto: miniatura y tamaño completo', () => {
  const foto = buildPhoto(
    {
      photoGuid: 'GUID-1',
      caption: 'En la montaña rusa',
      contributorFullName: 'Daniel Grimaldi',
      dateCreated: '2026-08-29T08:39:27Z',
      width: '2049',
      height: '1537',
      derivatives: {
        342: { fileSize: '149384', checksum: 'sum-342', width: '342', height: '257' },
        2049: { fileSize: '1051812', checksum: 'sum-2049', width: '2049', height: '1537' },
      },
    },
    urlFor,
  );
  assert.equal(foto.isVideo, false);
  assert.equal(foto.thumbUrl, 'https://cvws.icloud-content.com/342.jpg');
  assert.equal(foto.fullUrl, 'https://cvws.icloud-content.com/2049.jpg');
  assert.equal(foto.downloadChecksum, 'sum-2049');
  assert.equal(foto.contributor, 'Daniel Grimaldi');
});

test('normaliza un vídeo: póster y URL del vídeo', () => {
  const video = buildPhoto(
    {
      photoGuid: 'GUID-2',
      mediaAssetType: 'video',
      contributorFirstName: 'María',
      contributorLastName: 'López',
      derivatives: {
        342: { fileSize: '1000', checksum: 'sum-342' },
        PosterFrame: { fileSize: '2000', checksum: 'sum-poster' },
        '720p': { fileSize: '999999', checksum: 'sum-720p' },
      },
    },
    urlFor,
  );
  assert.equal(video.isVideo, true);
  assert.equal(video.posterUrl, 'https://cvws.icloud-content.com/poster.jpg');
  assert.equal(video.videoUrl, 'https://cvws.icloud-content.com/720p.mov');
  assert.equal(video.downloadChecksum, 'sum-720p');
  assert.equal(video.contributor, 'María López');
});

test('descarta fotos sin ninguna URL disponible', () => {
  const nada = buildPhoto({ photoGuid: 'GUID-3', derivatives: { 342: { checksum: 'no-existe' } } }, urlFor);
  assert.equal(nada, null);
});
