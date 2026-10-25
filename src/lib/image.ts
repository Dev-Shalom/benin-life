// Benin Gist photos: shrink a picked image on the phone BEFORE it is uploaded (docs/GIST.md). Storage is the scarce thing on a small
// plan, so a gist photo is at most `maxEdge` px on its longest side and re-encoded as JPEG until it fits under `maxBytes`.
export async function compressImage(file: File, maxBytes: number, maxEdge = 1080): Promise<Blob> {
  if (!file.type.startsWith('image/')) throw new Error('Pick a photo (JPEG, PNG or WebP).');
  const bmp = await loadBitmap(file);
  let scale = Math.min(1, maxEdge / Math.max(bmp.width, bmp.height));
  let quality = 0.82;
  for (let i = 0; i < 8; i++) {
    const w = Math.max(1, Math.round(bmp.width * scale));
    const h = Math.max(1, Math.round(bmp.height * scale));
    const canvas = document.createElement('canvas');
    canvas.width = w;
    canvas.height = h;
    const ctx = canvas.getContext('2d');
    if (!ctx) throw new Error('This browser cannot shrink photos.');
    ctx.fillStyle = '#fff';
    ctx.fillRect(0, 0, w, h);
    ctx.drawImage(bmp.source, 0, 0, w, h);
    const blob = await new Promise<Blob | null>((res) => canvas.toBlob(res, 'image/jpeg', quality));
    if (blob && blob.size <= maxBytes) { bmp.close(); return blob; }
    // too big: lower the quality first, then the size
    if (quality > 0.5) quality -= 0.12; else scale *= 0.8;
  }
  bmp.close();
  throw new Error('That photo is too big even after shrinking. Pick a smaller one.');
}

interface Bitmap { source: CanvasImageSource; width: number; height: number; close: () => void }

async function loadBitmap(file: File): Promise<Bitmap> {
  if (typeof createImageBitmap === 'function') {
    try {
      const b = await createImageBitmap(file);
      return { source: b, width: b.width, height: b.height, close: () => b.close() };
    } catch { /* fall back to <img> */ }
  }
  const url = URL.createObjectURL(file);
  try {
    const img = await new Promise<HTMLImageElement>((res, rej) => {
      const el = new Image();
      el.onload = () => res(el);
      el.onerror = () => rej(new Error('Could not read that photo.'));
      el.src = url;
    });
    return { source: img, width: img.naturalWidth, height: img.naturalHeight, close: () => URL.revokeObjectURL(url) };
  } catch (e) {
    URL.revokeObjectURL(url);
    throw e;
  }
}
