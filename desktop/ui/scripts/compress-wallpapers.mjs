/**
 * 压缩 public/wallpapers：最长边 ≤2560，统一 JPEG q82（保持比例，不裁切）。
 */
import fs from 'fs'
import path from 'path'
import sharp from 'sharp'
import { fileURLToPath } from 'url'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const dir = path.join(__dirname, '..', 'public', 'wallpapers')
const MAX = 2560

async function main() {
  const files = fs.readdirSync(dir).filter((f) => /\.(jpe?g|png|webp)$/i.test(f) && !f.includes('.__tmp__'))
  let before = 0
  let after = 0

  for (const name of files) {
    const src = path.join(dir, name)
    before += fs.statSync(src).size
    const base = name.replace(/\.[^.]+$/, '')
    const outJpg = path.join(dir, `${base}.jpg`)
    const tmp = path.join(dir, `${base}.__tmp__.jpg`)

    const img = sharp(src).rotate()
    const meta = await img.metadata()
    const w = meta.width || 0
    const h = meta.height || 0
    let pipeline = img
    if (w > MAX || h > MAX) {
      pipeline = pipeline.resize({
        width: w >= h ? MAX : undefined,
        height: h > w ? MAX : undefined,
        fit: 'inside',
        withoutEnlargement: true,
      })
    }
    await pipeline.jpeg({ quality: 82, mozjpeg: true }).toFile(tmp)

    if (path.resolve(src) !== path.resolve(outJpg) && fs.existsSync(src)) {
      fs.unlinkSync(src)
    }
    if (fs.existsSync(outJpg) && path.resolve(outJpg) !== path.resolve(tmp)) {
      fs.unlinkSync(outJpg)
    }
    fs.renameSync(tmp, outJpg)
    const size = fs.statSync(outJpg).size
    after += size
    console.log(`${base}.jpg  ${(size / 1024).toFixed(0)}KB  (${w}x${h})`)
  }

  console.log(`before=${(before / 1024 / 1024).toFixed(1)}MB after=${(after / 1024 / 1024).toFixed(1)}MB`)
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
