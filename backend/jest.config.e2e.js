module.exports = {
  moduleFileExtensions: ['js', 'ts', 'json'],
  roots: ['<rootDir>/test'],
  testRegex: '.*\\.e2e\\.spec\\.ts$',
  transform: {
    '^.+\\.ts$': 'ts-jest',
  },
  testEnvironment: 'node',
  testTimeout: 60000,
};
