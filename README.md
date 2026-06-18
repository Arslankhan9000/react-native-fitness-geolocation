# @micim/geo

Native fitness GPS for React Native. Drop-in replacement for `@react-native-community/geolocation`.

```bash
npm install @micim/geo
# or
yarn add @micim/geo
cd ios && pod install
```

```javascript
import Geolocation from '@micim/geo';
Geolocation.watchPosition(success, error, options);
```

## Documentation

| Doc | Description |
|-----|-------------|
| [docs/PRODUCTION.md](./docs/PRODUCTION.md) | Production guide |
| [docs/AI_CONTEXT.md](./docs/AI_CONTEXT.md) | AI / agent context |
| [docs/SETUP.md](./docs/SETUP.md) | Platform setup |
| [docs/PUBLISH.md](./docs/PUBLISH.md) | npm publish steps |
| [AGENTS.md](./AGENTS.md) | Cursor agent entry |

## MFC-App toggle (monorepo)

In MFC-App, flip one flag — no other code changes:

```javascript
// MFC-App/src/config/geolocation.config.js
export const USE_MICIM_GEO = false; // true after device verification
```

## License

MIT
