'use client'

import { useEffect, useRef } from 'react'

// The memory pool behind the hero: the same shader as the app (ios/Yearfilm/Views/MemoryPool.metal),
// ported to WebGL. Kept cheap: drawn at a fraction of screen resolution, about 30 fps, paused off
// screen or in a background tab, and a single still frame for prefers-reduced-motion. Without
// WebGL the canvas stays empty and the CSS glow behind it (.pool) is what shows.

const VERTEX = `
attribute vec2 a;
void main() { gl_Position = vec4(a, 0.0, 1.0); }
`

// highp: the hash below falls apart at 16-bit precision, which is what mediump is on Apple GPUs.
const FRAGMENT = `
precision highp float;
uniform vec2 size;
uniform float time;
uniform vec2 center;

float hash(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}
float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
             mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
  float v = 0.0, a = 0.5;
  mat2 m = mat2(1.6, 1.2, -1.2, 1.6);
  for (int i = 0; i < 4; i++) { v += a * noise(p); p = m * p; a *= 0.5; }
  return v;
}

void main() {
  vec2 position = vec2(gl_FragCoord.x, size.y - gl_FragCoord.y);
  float scale = min(size.x, size.y * 1.1);
  vec2 uv = (position - size * center) / scale;
  float r = length(uv);
  float angle = atan(uv.y, uv.x);

  float swirl = time * 0.035 + 0.35 / (r + 0.3);
  vec2 p = vec2(cos(angle + swirl), sin(angle + swirl)) * r * 1.7;

  vec2 q = vec2(fbm(p + time * 0.04), fbm(p + vec2(5.2, 1.3) - time * 0.035));
  vec2 w = vec2(fbm(p + 2.2 * q + vec2(1.7, 9.2) + time * 0.05),
                fbm(p + 2.2 * q + vec2(8.3, 2.8) - time * 0.045));
  float n = fbm(p + 2.4 * w);

  float ridge = 1.0 - abs(n * 2.0 - 1.0);
  float density = smoothstep(0.3, 0.62, fbm(p * 0.8 + vec2(11.0, 3.0) + time * 0.03));
  float filaments = pow(ridge, 9.0) * (0.25 + 0.75 * density);
  float haze = pow(ridge, 3.0) * (0.15 + 0.35 * density);

  float ring = smoothstep(0.06, 0.28, r) * (1.0 - smoothstep(0.5, 1.0, r));
  float light = (filaments * 1.6 + haze) * ring * 1.35;  // a touch brighter than the app: the web hero is wider and sits under a glass card

  vec3 deep = vec3(0.016, 0.031, 0.059);
  vec3 teal = vec3(0.10, 0.52, 0.86);
  vec3 ice = vec3(0.78, 0.95, 1.0);
  vec3 rgb = deep + teal * light + ice * pow(filaments * ring, 3.0) * 1.2;
  gl_FragColor = vec4(rgb, 1.0);
}
`

/** Draw at this fraction of the CSS size: the wisps are soft, so nobody sees the missing pixels. */
const RESOLUTION = 0.5
const FRAME_MS = 1000 / 30

export function MemoryPool({ centerX = 0.5, centerY = 0.45 }: { centerX?: number; centerY?: number }) {
  const canvas = useRef<HTMLCanvasElement>(null)

  useEffect(() => {
    const el = canvas.current
    const gl = el?.getContext('webgl', { antialias: false, alpha: false, powerPreference: 'low-power' })
    if (!el || !gl) return

    const program = link(gl)
    if (!program) return
    gl.useProgram(program)
    const buffer = gl.createBuffer()
    gl.bindBuffer(gl.ARRAY_BUFFER, buffer)
    gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW)
    const a = gl.getAttribLocation(program, 'a')
    gl.enableVertexAttribArray(a)
    gl.vertexAttribPointer(a, 2, gl.FLOAT, false, 0, 0)
    const uSize = gl.getUniformLocation(program, 'size')
    const uTime = gl.getUniformLocation(program, 'time')
    gl.uniform2f(gl.getUniformLocation(program, 'center'), centerX, centerY)

    const resize = () => {
      el.width = Math.max(1, Math.round(el.clientWidth * RESOLUTION))
      el.height = Math.max(1, Math.round(el.clientHeight * RESOLUTION))
      gl.viewport(0, 0, el.width, el.height)
      gl.uniform2f(uSize, el.width, el.height)
    }
    const draw = (seconds: number) => {
      gl.uniform1f(uTime, seconds)
      gl.drawArrays(gl.TRIANGLES, 0, 3)
    }

    const still = window.matchMedia('(prefers-reduced-motion: reduce)')
    // The clock starts a few seconds in, when the wisps are already well formed.
    const start = performance.now() - 12_000
    const now = () => (performance.now() - start) / 1000
    let frame = 0
    let last = 0
    let visible = true

    const tick = (time: number) => {
      frame = requestAnimationFrame(tick)
      if (time - last < FRAME_MS) return
      last = time
      draw(now())
    }
    const run = () => {
      cancelAnimationFrame(frame)
      draw(now())  // at once, so the pool is never blank while waiting for a frame (or for good, when still)
      if (!still.matches && visible && !document.hidden) frame = requestAnimationFrame(tick)
    }

    const sizer = new ResizeObserver(() => {
      resize()
      draw(now())
    })
    sizer.observe(el)
    const seen = new IntersectionObserver(([entry]) => {
      visible = entry.isIntersecting
      run()
    })
    seen.observe(el)
    document.addEventListener('visibilitychange', run)
    still.addEventListener('change', run)
    resize()
    run()

    return () => {
      cancelAnimationFrame(frame)
      sizer.disconnect()
      seen.disconnect()
      document.removeEventListener('visibilitychange', run)
      still.removeEventListener('change', run)
      // Free what this effect made, but keep the context: the canvas gets the same one back if
      // the effect runs again (React does that in development), and a lost one can't draw.
      gl.deleteBuffer(buffer)
      gl.deleteProgram(program)
    }
  }, [centerX, centerY])

  return (
    <div className="pool" aria-hidden="true">
      <canvas ref={canvas} />
    </div>
  )
}

function link(gl: WebGLRenderingContext) {
  const compile = (type: number, source: string) => {
    const shader = gl.createShader(type)!
    gl.shaderSource(shader, source)
    gl.compileShader(shader)
    if (gl.getShaderParameter(shader, gl.COMPILE_STATUS)) return shader
    console.warn('MemoryPool shader:', gl.getShaderInfoLog(shader))
    return null
  }
  const vs = compile(gl.VERTEX_SHADER, VERTEX)
  const fs = compile(gl.FRAGMENT_SHADER, FRAGMENT)
  if (!vs || !fs) return null
  const program = gl.createProgram()!
  gl.attachShader(program, vs)
  gl.attachShader(program, fs)
  gl.linkProgram(program)
  return gl.getProgramParameter(program, gl.LINK_STATUS) ? program : null
}
