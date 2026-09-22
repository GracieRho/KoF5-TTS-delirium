import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  base: '/',
  build: { outDir: 'dist', emptyOutDir: true },
  server: { proxy: { '/portal': 'http://127.0.0.1:8000', '/guardian/config': 'http://127.0.0.1:8000', '/internal': 'http://127.0.0.1:8000' } },
  test: { environment: 'jsdom', setupFiles: './src/test/setup.ts', css: true },
})
