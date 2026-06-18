# Publishing react-native-fitness-geolocation to npm

## Prerequisites

- npm account ([npmjs.com/signup](https://www.npmjs.com/signup))
- GitHub repo: `https://github.com/Arslankhan9000/react-native-fitness-geolocation`

## Local verification (before publish)

```bash
# 1. From monorepo — link locally
cd MFC-App
yarn install
cd ios && pod install && cd ..

# 2. Enable SDK in app (after testing with false first)
# Edit src/config/geolocation.config.js → USE_FITNESS_GEO = true

# 3. Verify platform config
node ../packages/react-native-fitness-geolocation/scripts/verify-setup.js

# 4. Test on real iOS device
yarn ios
# - Start activity, lock screen 10+ min, unlock — route should be complete

# 5. Toggle back to false to confirm legacy still works
# USE_FITNESS_GEO = false → rebuild → same flows work
```

## Git init (standalone repo)

```bash
cd packages/react-native-fitness-geolocation
git init
git add .
git commit -m "feat: initial release react-native-fitness-geolocation v2.0.0"
git branch -M main
git remote add origin git@github.com:Arslankhan9000/react-native-fitness-geolocation.git
git push -u origin main
```

## Publish to npm

```bash
cd packages/react-native-fitness-geolocation

# Build JS (runs on prepare, but verify)
yarn prepare

# Login once
npm login

# Dry run — check tarball contents
npm pack --dry-run

# Publish (unscoped — no --access flag needed)
npm publish

# Or beta tag first
npm publish --tag beta
```

## Version bumps

```bash
npm version patch   # 2.0.1
npm version minor   # 2.1.0
npm publish
git push && git push --tags
```

## Install in any React Native app

```bash
yarn add react-native-fitness-geolocation
cd ios && pod install
```

See [SETUP.md](./SETUP.md) for Info.plist and AndroidManifest requirements.

## MFC-App monorepo install (development)

```json
"react-native-fitness-geolocation": "file:../packages/react-native-fitness-geolocation"
```

After publish:

```json
"react-native-fitness-geolocation": "^2.0.0"
```
