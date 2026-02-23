const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
    calcLauncherIconSize, calcNeededRows, calcGridDropIndex
} = require('../helpers');

describe('calcLauncherIconSize', () => {
    it('returns override when positive', () => {
        assert.equal(calcLauncherIconSize(60, 2, 24), 24);
    });

    it('ignores override of 0 (auto mode)', () => {
        // floor(60/2) - 4 = 26
        assert.equal(calcLauncherIconSize(60, 2, 0), 26);
    });

    it('60px panel, 2 rows → 26px icons', () => {
        assert.equal(calcLauncherIconSize(60, 2, 0), 26);
    });

    it('60px panel, 1 row → 56px icons', () => {
        // floor(60/1) - 4 = 56
        assert.equal(calcLauncherIconSize(60, 1, 0), 56);
    });

    it('40px panel, 2 rows → 16px icons', () => {
        // floor(40/2) - 4 = 16
        assert.equal(calcLauncherIconSize(40, 2, 0), 16);
    });

    it('80px panel, 2 rows → 36px icons', () => {
        // floor(80/2) - 4 = 36
        assert.equal(calcLauncherIconSize(80, 2, 0), 36);
    });

    it('80px panel, 4 rows → 16px icons', () => {
        // floor(80/4) - 4 = 16
        assert.equal(calcLauncherIconSize(80, 4, 0), 16);
    });

    it('clamps to 12px minimum', () => {
        // floor(28/2) - 4 = 10 → clamped to 12
        assert.equal(calcLauncherIconSize(28, 2, 0), 12);
    });

    it('floors fractional results', () => {
        // floor(50/3) - 4 = floor(16.67) - 4 = 16 - 4 = 12
        assert.equal(calcLauncherIconSize(50, 3, 0), 12);
    });

    it('handles override regardless of panel height', () => {
        assert.equal(calcLauncherIconSize(10, 4, 48), 48);
    });
});

describe('calcNeededRows', () => {
    it('returns 1 row when all launchers fit', () => {
        // 400/30 = 13 slots per row, 5 launchers → 1 row
        assert.equal(calcNeededRows(400, 5, 30, 2), 1);
    });

    it('returns 2 rows when launchers overflow one row', () => {
        // 400/30 = 13 slots, 20 launchers → ceil(20/13) = 2
        assert.equal(calcNeededRows(400, 20, 30, 2), 2);
    });

    it('caps at maxRows', () => {
        // 400/30 = 13 slots, 50 launchers → ceil(50/13) = 4 → capped at 2
        assert.equal(calcNeededRows(400, 50, 30, 2), 2);
    });

    it('returns 1 for 0 launchers', () => {
        assert.equal(calcNeededRows(400, 0, 30, 2), 1);
    });

    it('returns 1 for 1 launcher', () => {
        assert.equal(calcNeededRows(400, 1, 30, 2), 1);
    });

    it('returns 1 when containerWidth is 0', () => {
        assert.equal(calcNeededRows(0, 10, 30, 2), 1);
    });

    it('returns 1 when cellSize is 0', () => {
        assert.equal(calcNeededRows(400, 10, 0, 2), 1);
    });

    it('returns 1 when maxRows is 1', () => {
        assert.equal(calcNeededRows(400, 50, 30, 1), 1);
    });

    it('returns exact rows for exact fit', () => {
        // 300/30 = 10 slots, 20 launchers → ceil(20/10) = 2
        assert.equal(calcNeededRows(300, 20, 30, 4), 2);
    });

    it('handles narrow container', () => {
        // 25/30 = 0 → max(1, 0) = 1 slot per row, 3 launchers → 3 rows, capped at 2
        assert.equal(calcNeededRows(25, 3, 30, 2), 2);
    });
});

describe('calcGridDropIndex', () => {
    it('returns 0 for top-left corner', () => {
        assert.equal(calcGridDropIndex(5, 5, 30, 30, 10, 20), 0);
    });

    it('returns correct index in first row', () => {
        // x=75 → col 2, y=5 → row 0, index = 0*10 + 2 = 2
        assert.equal(calcGridDropIndex(75, 5, 30, 30, 10, 20), 2);
    });

    it('returns correct index in second row', () => {
        // x=35 → col 1, y=35 → row 1, index = 1*10 + 1 = 11
        assert.equal(calcGridDropIndex(35, 35, 30, 30, 10, 20), 11);
    });

    it('clamps to totalItems', () => {
        // Very far right/bottom → large index, clamped to 20
        assert.equal(calcGridDropIndex(500, 500, 30, 30, 10, 20), 20);
    });

    it('clamps to 0 for negative coords', () => {
        assert.equal(calcGridDropIndex(-10, -10, 30, 30, 10, 20), 0);
    });

    it('returns 0 for 0-width cells', () => {
        assert.equal(calcGridDropIndex(50, 50, 0, 30, 10, 20), 0);
    });

    it('returns 0 for 0-height cells', () => {
        assert.equal(calcGridDropIndex(50, 50, 30, 0, 10, 20), 0);
    });

    it('returns 0 for 0 columns', () => {
        assert.equal(calcGridDropIndex(50, 50, 30, 30, 0, 20), 0);
    });

    it('handles single column grid', () => {
        // x=5 → col 0, y=65 → row 2, index = 2*1 + 0 = 2
        assert.equal(calcGridDropIndex(5, 65, 30, 30, 1, 5), 2);
    });

    it('handles drop at exact boundary', () => {
        // x=30 → col 1, y=0 → row 0, index = 0*10 + 1 = 1
        assert.equal(calcGridDropIndex(30, 0, 30, 30, 10, 20), 1);
    });
});
