import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import svgr from 'vite-plugin-svgr';
import path from 'path';

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react(), svgr()],
  base: '/',
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    outDir: 'dist',
    assetsDir: 'assets',
    // Disable source maps in production to avoid image layer extraction issues (overlayfs lchown on .js.map)
    sourcemap: false,
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://localhost:7091',
        changeOrigin: true,
      },
    },
  },
});
