const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const {
    calcLauncherIconSize, calcNeededRows, calcGridDropIndex, calcContainerColumns,
    calcContainerWidth, calcVisibleLauncherCount, calcIconSizeWithFallback, pickCellWidth
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

describe('calcContainerColumns', () => {
    // Core fix: items fill left-to-right before wrapping to a new row.
    // With few items (count <= maxRows), everything stays in one row.

    it('returns 0 for 0 items', () => {
        assert.equal(calcContainerColumns(0, 2), 0);
    });

    it('1 item, maxRows=2 → 1 column (single row)', () => {
        assert.equal(calcContainerColumns(1, 2), 1);
    });

    it('2 items, maxRows=2 → 2 columns (single row, not stacked)', () => {
        // This is the critical fix: 2 items should NOT stack into 1 column
        assert.equal(calcContainerColumns(2, 2), 2);
    });

    it('3 items, maxRows=2 → 2 columns (2+1 layout)', () => {
        assert.equal(calcContainerColumns(3, 2), 2);
    });

    it('4 items, maxRows=2 → 2 columns (2+2 layout)', () => {
        assert.equal(calcContainerColumns(4, 2), 2);
    });

    it('5 items, maxRows=2 → 3 columns (3+2 layout)', () => {
        assert.equal(calcContainerColumns(5, 2), 3);
    });

    it('10 items, maxRows=2 → 5 columns (5+5)', () => {
        assert.equal(calcContainerColumns(10, 2), 5);
    });

    it('1 item, maxRows=1 → 1 column', () => {
        assert.equal(calcContainerColumns(1, 1), 1);
    });

    it('3 items, maxRows=1 → 3 columns (all in single row)', () => {
        assert.equal(calcContainerColumns(3, 1), 3);
    });

    it('3 items, maxRows=3 → 3 columns (all in one row, not 1+1+1)', () => {
        assert.equal(calcContainerColumns(3, 3), 3);
    });

    it('4 items, maxRows=3 → 2 columns (2+2 in 2 rows)', () => {
        assert.equal(calcContainerColumns(4, 3), 2);
    });

    it('7 items, maxRows=3 → 3 columns (3+3+1)', () => {
        assert.equal(calcContainerColumns(7, 3), 3);
    });

    it('returns 0 for invalid maxRows', () => {
        assert.equal(calcContainerColumns(5, 0), 0);
    });

    it('returns 0 for negative count', () => {
        assert.equal(calcContainerColumns(-1, 2), 0);
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

describe('calcContainerWidth', () => {
    // Exact width = cols * cellWidth + (cols - 1) * spacing
    // Uses calcContainerColumns internally for column count.

    it('returns 0 for 0 items', () => {
        assert.equal(calcContainerWidth(0, 2, 30, 2, 0), 0);
    });

    it('returns 0 for invalid maxRows', () => {
        assert.equal(calcContainerWidth(5, 0, 30, 2, 0), 0);
    });

    it('returns 0 for invalid cellWidth', () => {
        assert.equal(calcContainerWidth(5, 2, 0, 2, 0), 0);
    });

    it('1 item, maxRows=2, cellW=30, spacing=2 → 30px', () => {
        // 1 col × 30 + 0 gaps = 30
        assert.equal(calcContainerWidth(1, 2, 30, 2, 0), 30);
    });

    it('2 items, maxRows=2 → 2 cols → 62px', () => {
        // 2 × 30 + 1 × 2 = 62
        assert.equal(calcContainerWidth(2, 2, 30, 2, 0), 62);
    });

    it('3 items, maxRows=2 → 2 cols → 62px', () => {
        // calcContainerColumns(3, 2) = 2
        // 2 × 30 + 1 × 2 = 62
        assert.equal(calcContainerWidth(3, 2, 30, 2, 0), 62);
    });

    it('5 items, maxRows=2 → 3 cols → 94px', () => {
        // calcContainerColumns(5, 2) = 3
        // 3 × 30 + 2 × 2 = 94
        assert.equal(calcContainerWidth(5, 2, 30, 2, 0), 94);
    });

    it('7 items, maxRows=2 → 4 cols → 126px', () => {
        // calcContainerColumns(7, 2) = 4
        // 4 × 30 + 3 × 2 = 126
        assert.equal(calcContainerWidth(7, 2, 30, 2, 0), 126);
    });

    it('10 items, maxRows=2 → 5 cols → 158px', () => {
        // 5 × 30 + 4 × 2 = 158
        assert.equal(calcContainerWidth(10, 2, 30, 2, 0), 158);
    });

    it('7 items, maxRows=3 → 3 cols → 94px', () => {
        // calcContainerColumns(7, 3) = 3
        // 3 × 30 + 2 × 2 = 94
        assert.equal(calcContainerWidth(7, 3, 30, 2, 0), 94);
    });

    it('handles spacing=0', () => {
        // 4 × 30 + 0 = 120
        assert.equal(calcContainerWidth(7, 2, 30, 0, 0), 120);
    });

    it('applies maxWidth cap', () => {
        // Calculated: 4 × 30 + 3 × 2 = 126, but maxWidth=100
        assert.equal(calcContainerWidth(7, 2, 30, 2, 100), 100);
    });

    it('maxWidth=0 means no limit', () => {
        assert.equal(calcContainerWidth(7, 2, 30, 2, 0), 126);
    });

    it('maxWidth larger than needed has no effect', () => {
        assert.equal(calcContainerWidth(7, 2, 30, 2, 500), 126);
    });
});

describe('calcVisibleLauncherCount', () => {
    // calcVisibleLauncherCount(totalCount, maxRows, cellWidth, spacing, maxWidth)
    // Returns how many launchers fit in the panel, reserving one column for chevron.

    it('maxWidth=0 → returns totalCount (no limit)', () => {
        assert.equal(calcVisibleLauncherCount(10, 2, 30, 2, 0), 10);
    });

    it('maxWidth negative → returns totalCount', () => {
        assert.equal(calcVisibleLauncherCount(10, 2, 30, 2, -5), 10);
    });

    it('totalCount=0 → returns 0', () => {
        assert.equal(calcVisibleLauncherCount(0, 2, 30, 2, 100), 0);
    });

    it('all fit naturally → returns totalCount', () => {
        // 4 items, maxRows=2 → 2 cols → width = 2*30 + 1*2 = 62. maxWidth=100 → all fit
        assert.equal(calcVisibleLauncherCount(4, 2, 30, 2, 100), 4);
    });

    it('basic overflow: 10 items, maxRows=2, cellW=30, spacing=2, maxWidth=100', () => {
        // maxCols = floor((100+2)/(30+2)) = floor(102/32) = 3
        // availCols = 3 - 1 = 2
        // visible = min(2*2, 10-1) = min(4, 9) = 4
        assert.equal(calcVisibleLauncherCount(10, 2, 30, 2, 100), 4);
    });

    it('maxWidth too small for any cell → 0', () => {
        // maxCols = floor((10+2)/(30+2)) = floor(12/32) = 0
        // availCols = 0 - 1 = -1 → 0
        assert.equal(calcVisibleLauncherCount(10, 2, 30, 2, 10), 0);
    });

    it('room for chevron only → 0', () => {
        // maxCols = floor((32+2)/(30+2)) = floor(34/32) = 1
        // availCols = 1 - 1 = 0
        assert.equal(calcVisibleLauncherCount(10, 2, 30, 2, 32), 0);
    });

    it('single row (maxRows=1)', () => {
        // 10 items, maxRows=1, cellW=30, spacing=2, maxWidth=200
        // naturalWidth = calcContainerWidth(10, 1, 30, 2, 0) = 10*30 + 9*2 = 318
        // maxCols = floor((200+2)/(30+2)) = floor(202/32) = 6
        // availCols = 6 - 1 = 5
        // visible = min(5*1, 10-1) = min(5, 9) = 5
        assert.equal(calcVisibleLauncherCount(10, 1, 30, 2, 200), 5);
    });

    it('1 launcher that fits → returns 1 (no overflow)', () => {
        // naturalWidth = calcContainerWidth(1, 2, 30, 2, 0) = 30
        // 30 <= 100 → all fit
        assert.equal(calcVisibleLauncherCount(1, 2, 30, 2, 100), 1);
    });

    it('1 launcher that does not fit → returns 0', () => {
        // naturalWidth = calcContainerWidth(1, 2, 30, 2, 0) = 30 > 10
        // maxCols = floor(12/32) = 0, availCols = -1 → 0
        assert.equal(calcVisibleLauncherCount(1, 2, 30, 2, 10), 0);
    });

    it('ensures at least 1 in overflow (does not return totalCount when overflow needed)', () => {
        // 5 items, maxRows=2, cellW=30, spacing=2, maxWidth=130
        // naturalWidth = calcContainerWidth(5, 2, 30, 2, 0) = 3*30 + 2*2 = 94
        // Wait — 94 <= 130, so all fit. Need a tighter case.
        // 5 items, maxRows=2, cellW=30, spacing=2, maxWidth=90
        // naturalWidth = 94 > 90 → overflow needed
        // maxCols = floor(92/32) = 2, availCols = 2 - 1 = 1
        // visible = min(1*2, 5-1) = min(2, 4) = 2
        assert.equal(calcVisibleLauncherCount(5, 2, 30, 2, 90), 2);
    });

    it('large overflow: 20 items, maxRows=2, cellW=30, spacing=2, maxWidth=200', () => {
        // naturalWidth = calcContainerWidth(20, 2, 30, 2, 0) = 10*30 + 9*2 = 318 > 200
        // maxCols = floor(202/32) = 6, availCols = 5
        // visible = min(5*2, 20-1) = min(10, 19) = 10
        assert.equal(calcVisibleLauncherCount(20, 2, 30, 2, 200), 10);
    });
});

describe('calcIconSizeWithFallback', () => {
    it('prefers override when > 0 and it fits in the panel', () => {
        // panel=80 / 2 rows = 40 per row; cap = 40 - 3 = 37; override 32 fits unchanged
        assert.equal(calcIconSizeWithFallback(80, 24, 2, 32), 32);
    });

    it('caps override to fit panel height / numberOfRows', () => {
        // panel=48 / 3 rows = 16 per row; cap = 16 - 3 = 13; override 16 caps to 13
        // This is the bug we hit on VM (48px panel, override=16, rows=3): 3 rows at
        // 19px each = 57px overflowing the 48px panel — row 3 got clipped.
        assert.equal(calcIconSizeWithFallback(48, 24, 3, 16), 13);
    });

    it('does not cap when override already fits', () => {
        // panel=60 / 3 rows = 20 per row; cap = 20 - 3 = 17; override 16 is ≤ 17
        assert.equal(calcIconSizeWithFallback(60, 24, 3, 16), 16);
    });

    it('uses panelHeight-derived size when override is 0 and panelHeight > 0', () => {
        // floor(60/2) - 4 = 26; cap = 60/2 - 3 = 27; 26 fits
        assert.equal(calcIconSizeWithFallback(60, 24, 2, 0), 26);
    });

    it('falls back to zoneIconSize when panelHeight is 0 (no cap applied)', () => {
        // cap only applies when panelHeight > 0
        assert.equal(calcIconSizeWithFallback(0, 24, 2, 0), 24);
    });

    it('falls back to zoneIconSize when panelHeight is missing', () => {
        assert.equal(calcIconSizeWithFallback(undefined, 22, 2, 0), 22);
    });

    it('uses 24 as final fallback when all inputs are zero/missing', () => {
        assert.equal(calcIconSizeWithFallback(0, 0, 2, 0), 24);
    });

    it('uses 24 as final fallback when zoneIconSize is negative', () => {
        assert.equal(calcIconSizeWithFallback(0, -1, 2, 0), 24);
    });

    it('honors override when panelHeight is 0 (no cap without panel info)', () => {
        assert.equal(calcIconSizeWithFallback(0, 0, 2, 48), 48);
    });

    it('still respects 12px minimum from calcLauncherIconSize path', () => {
        // auto: floor(28/2) - 4 = 10 → clamped to 12; cap = 28/2 - 3 = 11; 12 > 11 → cap to 11
        // Cap floor is 8, so we never go below 8 even for tiny panels.
        assert.equal(calcIconSizeWithFallback(28, 16, 2, 0), 11);
    });

    it('cap never shrinks below the 8px floor', () => {
        // panel=20 / 4 rows = 5 per row; cap would be 2 but floor is 8
        assert.equal(calcIconSizeWithFallback(20, 24, 4, 24), 8);
    });

    it('production config fits on a 60px+ panel', () => {
        // Prod: override=16, rows=3. On a 60px panel, cap = 17, override 16 fits.
        assert.equal(calcIconSizeWithFallback(60, 16, 3, 16), 16);
    });

    it('production config shrinks to fit on a 48px panel', () => {
        // Same override=16 rows=3 but panel=48 → bug-repro scenario; cap to 13
        assert.equal(calcIconSizeWithFallback(48, 16, 3, 16), 13);
    });
});

describe('pickCellWidth', () => {
    // Regression: _getCellWidth used to return 0 when natW was below
    // icon_size + 2, which starved FlowLayout and caused _updateIconSize to
    // ratchet the icon down to 1px. pickCellWidth must always be positive
    // when iconSize > 0 — it's better to over-size the container than to
    // leave it unsized.

    it('returns preferredWidth when it is >= iconSize', () => {
        // CSS has resolved; natural width (icon + padding) is the correct cell
        assert.equal(pickCellWidth(16, 32), 32);
    });

    it('returns iconSize + fallback padding when preferredWidth is below iconSize', () => {
        // CSS not resolved yet: natW reports the icon's intrinsic size only.
        // Must NOT return 0 — that would starve FlowLayout.
        assert.equal(pickCellWidth(16, 3), 20);
    });

    it('never returns 0 or negative for positive iconSize', () => {
        // Bug-repro inputs: iconSize=16, natW=3 (observed on VM with override=16).
        const result = pickCellWidth(16, 3);
        assert.ok(result > 0, `expected positive, got ${result}`);
    });

    it('returns 0 only when iconSize is 0 or negative (invalid)', () => {
        assert.equal(pickCellWidth(0, 100), 0);
        assert.equal(pickCellWidth(-1, 100), 0);
    });

    it('treats preferredWidth exactly equal to iconSize as resolved', () => {
        // natW === iconSize is the edge of "resolved" — use it (padding=0).
        assert.equal(pickCellWidth(16, 16), 16);
    });

    it('ignores preferredWidth when below iconSize by any margin', () => {
        // Even natW=15 (one below iconSize=16) is below the CSS-resolved
        // threshold and triggers the fallback.
        assert.equal(pickCellWidth(16, 15), 20);
    });
});
