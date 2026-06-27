const fs = require('fs');
const path = require('path');

describe('SyncEngine v2', () => {
  it('exports SyncEngine module', () => {
    const p = path.join(__dirname, '../src/SyncEngine.ts');
    const s = fs.readFileSync(p, 'utf8');
    expect(s).toContain('export class SyncEngine');
    expect(s).toContain('backoffBaseMs');
    expect(s).toContain('httpSync');
  });
});

