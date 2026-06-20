# Publishing react-native-fitness-geolocation to npm

## Prerequisites

- npm account ([npmjs.com/signup](https://www.npmjs.com/signup))
- GitHub repo: `https://github.com/Arslankhan9000/react-native-fitness-geolocation`

## Local verification (before publish)

```bash
# 1. From monorepo — link locally
cd lifeTracker
yarn install
cd ios && pod install && cd ..

# 2. Verify platform config
node node_modules/react-native-fitness-geolocation/scripts/verify-setup.js

# 3. Run on device
yarn ios
# - Start recording, lock screen 10+ min, unlock — route should be complete
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
yarn add react-native-fitness-geolocation@2.0.0
cd ios && pod install
```

### Yarn 4 — “quarantined” / YN0016 error

Yarn 4 defaults to blocking npm packages published in the last **24 hours**. If you see:

```
YN0016: The version for tag "latest" is quarantined
```

Use one of:

```bash
# One-time bypass
yarn add react-native-fitness-geolocation@2.0.0 --no-time-gate

# Or in .yarnrc.yml (lifeTracker example):
npmMinimalAgeGate: 0
npmPreapprovedPackages:
  - react-native-fitness-geolocation
```

Or wait ~24h after first publish — then `latest` installs normally.

See [SETUP.md](./SETUP.md) for Info.plist and AndroidManifest requirements.

## Monorepo install (development)

Use in **lifeTracker** or any sibling app:

```json
"react-native-fitness-geolocation": "file:../packages/react-native-fitness-geolocation"
```

After publish:

```json
"react-native-fitness-geolocation": "^2.0.0"
```
