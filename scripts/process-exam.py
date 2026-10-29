"""Scanned exam PDF + audios -> clean WebP pages, mono MP3s, manifest.json + validation report.

Usage: python scripts/process-exam.py <exam-config.json> <source-dir>
Output goes to <source-dir>/processed/ (outside the repo).
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import cv2
import numpy as np

DPI = 200
MAX_WIDTH = 1400
WEBP_QUALITY = 50
TESSERACT = shutil.which('tesseract') or r'C:\Program Files\Tesseract-OCR\tesseract.exe'


def renderPdf(pdfPath, outDir):
  subprocess.run(['pdftoppm', '-r', str(DPI), '-png', str(pdfPath), str(outDir / 'p')], check=True)
  return sorted(outDir.glob('p-*.png'))


def contentMask(gray):
  height, width = gray.shape
  ink = (gray < 140).astype(np.uint8)
  count, labels, stats, _ = cv2.connectedComponentsWithStats(ink, 8)
  keep = np.zeros_like(ink)
  for i in range(1, count):
    x, y, w, h, area = stats[i]
    touchesBorder = x <= 2 or y <= 2 or x + w >= width - 2 or y + h >= height - 2
    # Spine fold, tab shadow, specks: anything fully inside the outer edge band
    inEdgeBand = x + w < width * 0.08 or x > width * 0.92 or y + h < height * 0.04 or y > height * 0.96
    if touchesBorder or inEdgeBand or area <= 4:
      continue
    keep[labels == i] = 1
  return keep


def deskewAngle(mask):
  small = cv2.resize(mask * 255, (mask.shape[1] // 4, mask.shape[0] // 4))
  center = (small.shape[1] / 2, small.shape[0] / 2)
  bestAngle, bestScore = 0.0, -1
  # Text lines align when the row-profile variance peaks
  for angle in np.arange(-2, 2.01, 0.1):
    rotated = cv2.warpAffine(small, cv2.getRotationMatrix2D(center, angle, 1), small.shape[::-1])
    score = np.var(rotated.sum(axis=1))
    if score > bestScore:
      bestAngle, bestScore = angle, score
  return bestAngle


def photoRects(gray):
  dark = (gray < 200).astype(np.uint8)
  closed = cv2.morphologyEx(dark, cv2.MORPH_CLOSE, np.ones((15, 15), np.uint8))
  count, _, stats, _ = cv2.connectedComponentsWithStats(closed, 8)
  rects = []
  for i in range(1, count):
    x, y, w, h, _ = stats[i]
    # Photos are big and mostly dark; text blocks and forms are mostly paper
    if w > 150 and h > 150 and dark[y:y + h, x:x + w].mean() > 0.4:
      rects.append((x, y, w, h))
  return rects


def cleanPage(pngPath, masks):
  gray = cv2.cvtColor(cv2.imread(str(pngPath)), cv2.COLOR_BGR2GRAY)
  for x0, y0, x1, y1 in masks:
    gray[y0:y1, x0:x1] = 255

  height, width = gray.shape
  mask = contentMask(gray)
  rotation = cv2.getRotationMatrix2D((width / 2, height / 2), deskewAngle(mask), 1)
  gray = cv2.warpAffine(gray, rotation, (width, height), flags=cv2.INTER_CUBIC, borderValue=255)
  mask = cv2.warpAffine(mask, rotation, (width, height), flags=cv2.INTER_NEAREST, borderValue=0)

  ys, xs = np.nonzero(mask)
  pad = 40
  crop = gray[max(ys.min() - pad, 0):ys.max() + pad, max(xs.min() - pad, 0):xs.max() + pad]

  # Paper -> white hides show-through from the back page; photos keep their tones
  paper = crop[crop > 180]
  white = np.percentile(paper, 30) - 25 if paper.size else 230
  black = np.percentile(crop, 1)
  leveled = (np.clip((crop.astype(np.float32) - black) / (white - black), 0, 1) * 255).astype(np.uint8)
  for x, y, w, h in photoRects(crop):
    leveled[y:y + h, x:x + w] = crop[y:y + h, x:x + w]

  if leveled.shape[1] > MAX_WIDTH:
    scale = MAX_WIDTH / leveled.shape[1]
    leveled = cv2.resize(leveled, (MAX_WIDTH, round(leveled.shape[0] * scale)), interpolation=cv2.INTER_AREA)
  return leveled


def detectQuestionNumbers(image, tmpDir):
  pngPath = tmpDir / 'ocr.png'
  cv2.imwrite(str(pngPath), image)
  text = subprocess.run(
    [TESSERACT, str(pngPath), 'stdout', '--psm', '3'], capture_output=True, text=True, encoding='utf-8',
  ).stdout
  numbers = {int(n) for n in re.findall(r'(?m)^\s*(\d{1,3})\s*[.,:;]', text)}
  for first, last in re.findall(r'Questions?\s+(\d{1,3})\s*[-–—]\s*(\d{1,3})', text):
    numbers.update({int(first), int(last)})
  return {n for n in numbers if 1 <= n <= 200}


def audioDuration(path):
  result = subprocess.run(
    ['ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', str(path)],
    capture_output=True, text=True,
  )
  return float(result.stdout.strip())


def normalizeAudio(sourcePath, outPath):
  # Mono 64 kbps is enough for speech and cuts storage/egress
  subprocess.run(
    ['ffmpeg', '-y', '-v', 'error', '-i', str(sourcePath), '-ac', '1', '-b:a', '64k', '-map_metadata', '-1', str(outPath)],
    check=True,
  )


def validatePages(config, pageCount, detectedByPage):
  errors = []
  if pageCount != len(config['pages']):
    errors.append(f'El PDF tiene {pageCount} páginas y la config describe {len(config["pages"])}')

  covered = set()
  for page in config['pages']:
    if page['first_q'] is None:
      continue
    expected = set(range(page['first_q'], page['last_q'] + 1))
    covered |= expected
    detected = detectedByPage[page['pdf_page']]
    inside = detected & expected
    outside = detected - expected
    label = f'Pág. {page["pdf_page"]} ({page["first_q"]}-{page["last_q"]})'
    if not inside:
      errors.append(f'{label}: el OCR no encontró ningún número del rango')
    elif len(outside) > len(inside):
      errors.append(f'{label}: el OCR encontró más números fuera del rango: {sorted(outside)}')

  for part in config['parts']:
    missing = set(range(part['first_q'], part['last_q'] + 1)) - covered
    if missing:
      errors.append(f'Parte {part["part"]}: preguntas sin página {sorted(missing)}')
  return errors


def processAudio(config, sourceDir, outDir):
  errors = []
  durations = {}
  for part in config['parts']:
    if part['section'] != 'listening':
      continue
    path = sourceDir / part['audio']
    if not path.exists():
      errors.append(f'Parte {part["part"]}: falta el audio {part["audio"]}')
      continue
    outPath = outDir / f'audio/part-{part["part"]}.mp3'
    normalizeAudio(path, outPath)
    sizeMb = outPath.stat().st_size / 1024 / 1024
    print(f'audio/part-{part["part"]}.mp3  {sizeMb:.1f} MB')
    duration = audioDuration(outPath)
    durations[part['part']] = round(duration)
    if not 60 <= duration <= 1800:
      errors.append(f'Parte {part["part"]}: duración sospechosa ({duration:.0f} s)')
  return errors, durations


def main(configPath, sourceDir):
  config = json.loads(configPath.read_text(encoding='utf-8'))
  examId = config['exam_id']
  outDir = sourceDir / 'processed'
  (outDir / 'pages').mkdir(parents=True, exist_ok=True)
  (outDir / 'audio').mkdir(exist_ok=True)

  detectedByPage = {}
  pagesManifest = []
  with tempfile.TemporaryDirectory() as tmp:
    tmpDir = Path(tmp)
    pngs = renderPdf(sourceDir / config['pdf'], tmpDir)
    for order, page in enumerate(config['pages'], start=1):
      image = cleanPage(pngs[page['pdf_page'] - 1], page.get('masks', []))
      fileName = f'pages/{order}.webp'
      cv2.imwrite(str(outDir / fileName), image, [cv2.IMWRITE_WEBP_QUALITY, WEBP_QUALITY])
      detectedByPage[page['pdf_page']] = detectQuestionNumbers(image, tmpDir)
      sizeKb = (outDir / fileName).stat().st_size // 1024
      print(f'{fileName}  part {page["part"]}  q {page["first_q"]}-{page["last_q"]}  {sizeKb} KB')
      pagesManifest.append({
        'part': page['part'],
        'page_order': order,
        'first_q': page['first_q'],
        'last_q': page['last_q'],
        'image_path': f'{examId}/{fileName}',
        'file': fileName,
      })

  errors = validatePages(config, len(pngs), detectedByPage)
  audioErrors, durations = processAudio(config, sourceDir, outDir)
  errors += audioErrors

  parts = []
  for part in config['parts']:
    isListening = part['section'] == 'listening'
    parts.append({
      'part': part['part'],
      'section': part['section'],
      'first_q': part['first_q'],
      'last_q': part['last_q'],
      'choices_count': part['choices_count'],
      'audio_path': f'{examId}/audio/part-{part["part"]}.mp3' if isListening else None,
      'file': f'audio/part-{part["part"]}.mp3' if isListening else None,
      'audio_duration_s': durations.get(part['part']),
    })

  manifest = {
    'exam_id': examId,
    'title': config['title'],
    # Siempre queda en draft: solo el docente aprueba tras la revisión manual
    'status': 'draft',
    'parts': parts,
    'pages': pagesManifest,
    'errors': errors,
  }
  (outDir / 'manifest.json').write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')

  print(f'\n{len(pagesManifest)} páginas -> {outDir}')
  print('Validaciones OK' if not errors else 'Errores:\n- ' + '\n- '.join(errors))


if __name__ == '__main__':
  if len(sys.argv) != 3:
    sys.exit(__doc__)
  main(Path(sys.argv[1]), Path(sys.argv[2]))
