import react from '@vitejs/plugin-react'
import { defineConfig } from 'vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  build: {
    rolldownOptions: {
      output: {
        codeSplitting: {
          // only the matched packages (not react, which they import) go into these chunks
          includeDependenciesRecursively: false,
          groups: [
            // three.js and react-three-fiber in their own lazy vendor chunks: they only load with the first 3D view,
            // and stay cached in the browser when the game's own avatar/scene code changes.
            { name: 'three', test: /node_modules[\\/]three[\\/]/, priority: 20 },
            { name: 'r3f', test: /node_modules[\\/](@react-three|react-reconciler|its-fine|react-use-measure|suspend-react)[\\/]/, priority: 10 },
          ],
        },
      },
    },
  },
})
