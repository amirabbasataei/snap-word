/// <reference types="vitest/config" />
import { fileURLToPath, URL } from 'node:url'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { defineConfig } from 'vite'

// The panel is served by the Go server under /admin/ (embedded build). Behind
// a proxy that mounts it elsewhere (e.g. nginx `/zanjir/` → backend `/`), build
// with PANEL_PREFIX=/zanjir so asset, router and API URLs carry the prefix.
// `pnpm dev` proxies the API to the local backend.
const prefix = (process.env.PANEL_PREFIX ?? '').replace(/\/+$/, '')

export default defineConfig({
  base: `${prefix}/admin/`,
  plugins: [react(), tailwindcss()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  build: {
    outDir: '../backend/internal/adminui/dist',
    emptyOutDir: false, // keep dist/.gitkeep; the build script clears the rest
    sourcemap: false,
  },
  server: {
    proxy: { '/api': { target: 'http://localhost:8080', changeOrigin: false } },
  },
  test: {
    environment: 'jsdom',
    globals: true,
    setupFiles: ['./src/test/setup.ts'],
    css: false,
  },
})
