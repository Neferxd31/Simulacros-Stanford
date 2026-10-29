// Uploads a processed exam (pages, audios, manifest) to Supabase Storage and tables.
// Usage: node --env-file=.env.local scripts/upload-exam.js <processed-dir>
import { readFile } from 'node:fs/promises'
import path from 'node:path'
import { createClient } from '@supabase/supabase-js'

const BUCKET = 'exams'

const processedDir = process.argv[2]
if (!processedDir) {
  console.error('Usage: node --env-file=.env.local scripts/upload-exam.js <processed-dir>')
  process.exit(1)
}

const supabase = createClient(process.env.VITE_SUPABASE_URL, process.env.SUPABASE_SECRET_KEY)
const manifest = JSON.parse(await readFile(path.join(processedDir, 'manifest.json'), 'utf8'))

const uploadFile = async (file, storagePath, contentType) => {
  const body = await readFile(path.join(processedDir, file))
  const { error } = await supabase.storage.from(BUCKET).upload(storagePath, body, { contentType, upsert: true })
  if (error) throw new Error(`${storagePath}: ${error.message}`)
  console.log(`uploaded ${storagePath}`)
}

const check = ({ error }, step) => {
  if (error) throw new Error(`${step}: ${error.message}`)
}

for (const page of manifest.pages) {
  await uploadFile(page.file, page.image_path, 'image/webp')
}
for (const part of manifest.parts.filter((part) => part.audio_path)) {
  await uploadFile(part.file, part.audio_path, 'audio/mpeg')
}

// Volver a cargar deja el simulacro en draft: el contenido cambió y hay que revisarlo de nuevo
check(await supabase.from('exams').upsert({ id: manifest.exam_id, title: manifest.title, status: 'draft' }), 'exams')
// Deleting parts cascades to pages, so a re-run replaces the whole structure
check(await supabase.from('exam_parts').delete().eq('exam_id', manifest.exam_id), 'delete exam_parts')
check(await supabase.from('exam_parts').insert(manifest.parts.map(({ file: _file, ...part }) => ({ exam_id: manifest.exam_id, ...part }))), 'exam_parts')
check(await supabase.from('exam_pages').insert(manifest.pages.map(({ file: _file, ...page }) => ({ exam_id: manifest.exam_id, ...page }))), 'exam_pages')

console.log(`\n${manifest.exam_id}: ${manifest.pages.length} pages, ${manifest.parts.length} parts loaded as draft`)
if (manifest.errors.length) console.log(`Validation warnings to review:\n- ${manifest.errors.join('\n- ')}`)
