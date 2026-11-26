// Downloads (or uploads) every file of a Supabase Storage bucket, keeping
// the folder layout, through the Storage API with the service-role key.
// Used by the nightly backup (CR-25B B5) and by docs/RESTORE.md.
//
//   node tool/backup/storage_files.mjs download <bucket> <folder>
//   node tool/backup/storage_files.mjs upload   <bucket> <folder>
//
// Needs SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY. Prints a count only,
// never a key or a file's contents.
import { mkdir, readdir, readFile, writeFile, stat } from 'node:fs/promises';
import { dirname, join, relative, sep } from 'node:path';

const [mode, bucket, folder] = process.argv.slice(2);
const base = process.env.SUPABASE_URL?.replace(/\/$/, '');
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!['download', 'upload'].includes(mode) || !bucket || !folder || !base || !key) {
  console.error('Usage: storage_files.mjs download|upload <bucket> <folder> (with SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY)');
  process.exit(2);
}
const headers = { Authorization: `Bearer ${key}`, apikey: key };

async function call(path, init = {}) {
  for (let attempt = 1; ; attempt++) {
    const response = await fetch(`${base}/storage/v1/${path}`, { ...init, headers: { ...headers, ...init.headers } });
    if (response.ok) return response;
    if (attempt >= 3 || response.status < 500) {
      throw new Error(`${init.method ?? 'GET'} ${path.split('/')[0]}: HTTP ${response.status}`);
    }
    await new Promise((resolve) => setTimeout(resolve, 2000 * attempt));
  }
}

/** Every object path in the bucket (folders are listed without an id). */
async function listAll(prefix = '') {
  const found = [];
  for (let offset = 0; ; offset += 1000) {
    const response = await call(`object/list/${bucket}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefix, limit: 1000, offset, sortBy: { column: 'name', order: 'asc' } }),
    });
    const entries = await response.json();
    for (const entry of entries) {
      const path = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id == null) found.push(...(await listAll(path)));
      else found.push(path);
    }
    if (entries.length < 1000) return found;
  }
}

const types = { png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg', webp: 'image/webp', gif: 'image/gif', zip: 'application/zip', pdf: 'application/pdf' };
const typeOf = (path) => types[path.split('.').pop().toLowerCase()] ?? 'application/octet-stream';

async function walk(dir) {
  const files = [];
  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);
    if (entry.isDirectory()) files.push(...(await walk(full)));
    else files.push(full);
  }
  return files;
}

if (mode === 'download') {
  const paths = await listAll();
  let bytes = 0;
  for (const path of paths) {
    const response = await call(`object/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`);
    const data = Buffer.from(await response.arrayBuffer());
    const target = join(folder, ...path.split('/'));
    await mkdir(dirname(target), { recursive: true });
    await writeFile(target, data);
    bytes += data.length;
  }
  console.log(`${bucket}: downloaded ${paths.length} files, ${bytes} bytes`);
} else {
  await stat(folder);
  const files = await walk(folder);
  for (const file of files) {
    const path = relative(folder, file).split(sep).join('/');
    await call(`object/${bucket}/${path.split('/').map(encodeURIComponent).join('/')}`, {
      method: 'POST',
      headers: { 'x-upsert': 'true', 'Content-Type': typeOf(path) },
      body: await readFile(file),
    });
  }
  console.log(`${bucket}: uploaded ${files.length} files`);
}
