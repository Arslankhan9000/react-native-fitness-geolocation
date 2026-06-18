# Publishing @micim/geo to npm

## Prerequisites

- npm account with access to `@micim` scope (or publish as unscoped — update `package.json`)
- GitHub repo: `https://github.com/micim/geo`

## Local verification (before publish)

```bash
# 1. From monorepo — link locally
cd MFC-App
yarn install
cd ios && pod install && cd ..

# 2. Enable SDK in app (after testing with false first)
# Edit src/config/geolocation.config.js → USE_MICIM_GEO = true

# 3. Verify platform config
node ../packages/micim-geo/scripts/verify-setup.js

# 4. Test on real iOS device
yarn ios
# - Start activity, lock screen 10+ min, unlock — route should be complete

# 5. Toggle back to false to confirm legacy still works
# USE_MICIM_GEO = false → rebuild → same flows work
```

## Git init (standalone repo)

```bash
cd packages/micim-geo
git init
git add .
git commit -m "feat: initial release @micim/geo v2.0.0"
git branch -M main
git remote add origin git@github.com:micim/geo.git
git push -u origin main
```

## Publish to npm

```bash
cd packages/micim-geo

# Build JS (runs on prepare, but verify)
yarn prepare

# Login once
npm login

# Dry run — check tarball contents
npm pack --dry-run

# Publish (scoped public)
npm publish --access public

# Or beta tag first
npm publish --access public --tag beta
```

## Version bumps

```bash
npm version patch   # 2.0.1
npm version minor   # 2.1.0
npm publish --access public
git push && git push --tags
```

## Install in any React Native app

```bash
yarn add @micim/geo
cd ios && pod install
```

See [SETUP.md](./SETUP.md) for Info.plist and AndroidManifest requirements.

## MFC-App monorepo install (development)

```json
"@micim/geo": "file:../packages/micim-geo"
```

After publish:

```json
"@micim/geo": "^2.0.0"
```
