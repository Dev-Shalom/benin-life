import react from '@vitejs/plugin-react'
import { execSync } from 'node:child_process'
import { defineConfig, type Plugin } from 'vite'

// S1 update notice: every build gets an id (git SHA + build time). It is baked into the app as
// import.meta.env.VITE_BUILD_ID and written to dist/version.json; open tabs poll that file and offer
// a Refresh when it changes (src/lib/update.ts).
function gitSha(): string {
  const env = process.env.VERCEL_GIT_COMMIT_SHA
  if (env) return env.slice(0, 7)
  try {
    return execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] }).toString().trim()
  } catch {
    return 'nogit'
  }
}
const BUILT_AT = new Date().toISOString()
const BUILD_ID = `${gitSha()}-${Date.now().toString(36)}`

function versionFile(): Plugin {
  return {
    name: 'bl-version-json',
    apply: 'build',
    generateBundle() {
      this.emitFile({ type: 'asset', fileName: 'version.json', source: JSON.stringify({ id: BUILD_ID, built_at: BUILT_AT }) + '\n' })
    },
  }
}

// https://vite.dev/config/
export default defineConfig({
  plugins: [react(), versionFile()],
  // PAY: Vercel holds the Paystack public key as PAYSTACK_PUBLIC_KEY (public by design). Only that exact
  // family is exposed; never widen this to 'PAYSTACK_' (it would match PAYSTACK_SECRET_KEY).
  envPrefix: ['VITE_', 'PAYSTACK_PUBLIC_'],
  define: {
    'import.meta.env.VITE_BUILD_ID': JSON.stringify(BUILD_ID),
  },
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
