const fs = require('fs');
const path = require('path');

describe('Health API', () => {
  it('exports Health module', () => {
    const p = path.join(__dirname, '../src/Health.ts');
    const s = fs.readFileSync(p, 'utf8');
    expect(s).toContain('export const Health');
    expect(s).toContain('getHealth()');
  });
});

