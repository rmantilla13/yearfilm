import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
// Renders the Yearfilm mark from the same math as ios/Yearfilm/Views/MemoryPool.metal:
// three arcs of light swirling around one bright memory. Seed 27 is the shipped mark.
//   swiftc -O scripts/brand-mark.swift -o /tmp/mark && /tmp/mark icon.png 1024 icon 27
// usage: mark <out.png> <size> <variant: icon|transparent> <seed> [orb 0/1] [ringRadius] [twist]
let a = CommandLine.arguments
let out = a[1], N = Int(a[2])!, transparent = a[3] == "transparent", seed = Float(a[4])!
let orb = a.count > 5 ? a[5] == "1" : true
let R0: Float = a.count > 6 ? Float(a[6])! : 0.30
let twist: Float = a.count > 7 ? Float(a[7])! : 0.35
func fract(_ x: Float) -> Float { x - floor(x) }
func hash(_ x: Float, _ y: Float) -> Float { var px = fract(x * 123.34), py = fract(y * 456.21); let d = px * (px + 45.32) + py * (py + 45.32); px += d; py += d; return fract(px * py) }
func mix(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
func noise(_ x: Float, _ y: Float) -> Float { let ix = floor(x), iy = floor(y), fx = x - ix, fy = y - iy; let ux = fx*fx*(3-2*fx), uy = fy*fy*(3-2*fy)
  return mix(mix(hash(ix,iy), hash(ix+1,iy), ux), mix(hash(ix,iy+1), hash(ix+1,iy+1), ux), uy) }
func fbm(_ x0: Float, _ y0: Float) -> Float { var v: Float = 0, amp: Float = 0.5, x = x0, y = y0
  for _ in 0..<5 { v += amp * noise(x, y); let nx = 1.6*x + 1.2*y, ny = -1.2*x + 1.6*y; x = nx; y = ny; amp *= 0.5 }; return v }
func smooth(_ e0: Float, _ e1: Float, _ x: Float) -> Float { let t = max(0, min(1, (x - e0) / (e1 - e0))); return t*t*(3-2*t) }
var px = [UInt8](repeating: 0, count: N * N * 4)
let t = seed
for j in 0..<N { for i in 0..<N {
  let ux = (Float(i) + 0.5) / Float(N) - 0.5, uy = (Float(j) + 0.5) / Float(N) - 0.5
  let r = sqrt(ux*ux + uy*uy), ang = atan2(uy, ux)
  let sw = t * 0.035 + twist / (r + 0.3)
  let px0 = cos(ang + sw) * r * 3.2, py0 = sin(ang + sw) * r * 3.2
  let qx = fbm(px0 + t*0.04, py0), qy = fbm(px0 + 5.2, py0 + 1.3 - t*0.035)
  let wx = fbm(px0 + 2.2*qx + 1.7, py0 + 2.2*qy + 9.2), wy = fbm(px0 + 2.2*qx + 8.3, py0 + 2.2*qy + 2.8)
  let n = fbm(px0 + 2.4*wx, py0 + 2.4*wy)
  let ridge = 1 - abs(n*2 - 1)
  // Spiral arcs of light swirling into the pool, varied by the noise so they read as wisps.
  let spiral = ang * 3 + log(max(r, 0.001)) * 7 + 2.2 * (n - 0.5) + t
  let arcs = pow(0.5 + 0.5 * cos(spiral), 14) * (0.45 + 0.9 * qx)
  let ringD = (r - R0) / 0.075
  let ring = exp(-ringD*ringD)
  let outer = exp(-pow((r - R0) / 0.16, 2))
  let fil = (arcs * 1.5 + pow(ridge, 9) * 0.6) * ring * 1.6
  let haze = outer * 0.16 + ring * 0.12
  var light = fil + haze
  // The memory: a small bright orb falling into the pool.
  var core: Float = 0
  if orb { let ox = ux, oy = uy; let d = sqrt(ox*ox + oy*oy); core = exp(-d*d/0.00045) * 1.5 + exp(-d*d/0.004) * 0.3; light += core }
  let deep: (Float, Float, Float) = (0.016, 0.031, 0.065), teal: (Float, Float, Float) = (0.10, 0.55, 0.92), ice: (Float, Float, Float) = (0.80, 0.96, 1.0)
  let hot = min(1, pow(fil, 2.2) * 0.9 + core * 0.8)
  var rr = teal.0 * light + ice.0 * hot, gg = teal.1 * light + ice.1 * hot, bb = teal.2 * light + ice.2 * hot
  let k = (j*N + i) * 4
  if transparent {
    let alpha = min(1, max(rr, max(gg, bb)) * 1.1)
    let s: Float = alpha > 0.001 ? 1/alpha : 0
    px[k] = UInt8(min(255, rr*s*alpha*255)); px[k+1] = UInt8(min(255, gg*s*alpha*255)); px[k+2] = UInt8(min(255, bb*s*alpha*255)); px[k+3] = UInt8(alpha*255)
  } else {
    let vig = 1 - 0.45 * smooth(0.2, 0.75, r)
    rr += deep.0 * vig; gg += deep.1 * vig; bb += deep.2 * vig
    px[k] = UInt8(min(255, rr*255)); px[k+1] = UInt8(min(255, gg*255)); px[k+2] = UInt8(min(255, bb*255)); px[k+3] = 255
  }
}}
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let info = transparent ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
let ctx = CGContext(data: &px, width: N, height: N, bitsPerComponent: 8, bytesPerRow: N*4, space: cs, bitmapInfo: info)!
let img = ctx.makeImage()!
let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: out) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, img, nil); CGImageDestinationFinalize(dest)
