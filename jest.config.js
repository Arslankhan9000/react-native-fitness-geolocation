module.exports = {
  testMatch: ['**/__tests__/**/*.test.{ts,js}'],
  modulePathIgnorePatterns: ['<rootDir>/lib/', '<rootDir>/node_modules/'],
  watchman: false,
  transform: {
    '^.+\\.ts$': ['ts-jest', { tsconfig: { module: 'commonjs', esModuleInterop: true } }],
  },
  testEnvironment: 'node',
};
