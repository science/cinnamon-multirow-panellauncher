/**
 * Pure computation helpers for multi-row panel launchers.
 * No Cinnamon/GJS dependencies — testable in Node.js.
 */

/**
 * Calculate icon size for launcher buttons given panel height and row count.
 * @param {number} panelHeight - Total panel height in pixels
 * @param {number} numberOfRows - Number of rows (1-4)
 * @param {number} overrideSize - User override (0 = auto-scale)
 * @returns {number} Icon size in pixels
 */
function calcLauncherIconSize(panelHeight, numberOfRows, overrideSize) {
    if (overrideSize > 0) return overrideSize;
    return Math.max(12, Math.floor(panelHeight / numberOfRows) - 4);
}

/**
 * Calculate how many rows are needed for the given launcher count.
 * @param {number} containerWidth - Available width in pixels
 * @param {number} launcherCount - Number of launcher icons
 * @param {number} cellSize - Width per cell in pixels (icon + padding)
 * @param {number} maxRows - Maximum allowed rows (1-4)
 * @returns {number} Number of rows (1 to maxRows)
 */
function calcNeededRows(containerWidth, launcherCount, cellSize, maxRows) {
    if (launcherCount <= 0 || containerWidth <= 0 || cellSize <= 0 || maxRows <= 0) {
        return 1;
    }
    let launchersPerRow = Math.max(1, Math.floor(containerWidth / cellSize));
    let needed = Math.ceil(launcherCount / launchersPerRow);
    return Math.max(1, Math.min(needed, maxRows));
}

/**
 * Calculate the number of columns for a container given item count and max rows.
 * Items fill left-to-right first; only wraps to a new row when needed.
 * When count <= maxRows, all items stay in one row (no unnecessary stacking).
 * @param {number} count - Number of items
 * @param {number} maxRows - Maximum allowed rows (1-4)
 * @returns {number} Number of columns (0 if no items or invalid)
 */
function calcContainerColumns(count, maxRows) {
    if (count <= 0 || maxRows <= 0) return 0;
    if (count <= maxRows) return count;
    return Math.ceil(count / maxRows);
}

/**
 * Calculate the container width for a multi-row grid of items.
 * Uses exact cell-width math: cols * cellWidth + (cols - 1) * spacing.
 * @param {number} count - Number of items
 * @param {number} maxRows - Maximum allowed rows (1-4)
 * @param {number} cellWidth - Width per cell in pixels (icon + padding)
 * @param {number} spacing - Column spacing in pixels
 * @param {number} maxWidth - Maximum width cap (0 = no limit)
 * @returns {number} Container width in pixels (0 if no items or invalid)
 */
function calcContainerWidth(count, maxRows, cellWidth, spacing, maxWidth) {
    if (count <= 0 || maxRows <= 0 || cellWidth <= 0) return 0;
    let cols = calcContainerColumns(count, maxRows);
    let width = cols * cellWidth + Math.max(0, cols - 1) * spacing;
    if (maxWidth > 0 && width > maxWidth) width = maxWidth;
    return width;
}

/**
 * Calculate how many launchers fit in the panel before overflow.
 * Reserves one column for the chevron indicator when overflow is needed.
 * Returns totalCount when all fit or maxWidth <= 0 (no limit).
 * @param {number} totalCount - Total number of launchers
 * @param {number} maxRows - Maximum allowed rows (1-4)
 * @param {number} cellWidth - Width per cell in pixels (icon + padding)
 * @param {number} spacing - Column spacing in pixels
 * @param {number} maxWidth - Maximum container width (0 = no limit)
 * @returns {number} Number of visible launchers (0 to totalCount)
 */
function calcVisibleLauncherCount(totalCount, maxRows, cellWidth, spacing, maxWidth) {
    if (maxWidth <= 0 || totalCount <= 0) return totalCount;
    let naturalWidth = calcContainerWidth(totalCount, maxRows, cellWidth, spacing, 0);
    if (naturalWidth <= maxWidth) return totalCount; // all fit, no overflow
    let maxCols = Math.floor((maxWidth + spacing) / (cellWidth + spacing));
    let availCols = maxCols - 1; // reserve 1 column for chevron
    if (availCols <= 0) return 0; // only chevron fits (or nothing)
    return Math.min(availCols * maxRows, totalCount - 1); // at least 1 in overflow
}

/**
 * Calculate the drop index for a 2D grid given pointer coordinates.
 * @param {number} x - Pointer x relative to container
 * @param {number} y - Pointer y relative to container
 * @param {number} cellWidth - Width of each grid cell
 * @param {number} cellHeight - Height of each grid cell
 * @param {number} cols - Number of columns in the grid
 * @param {number} totalItems - Total number of items in the grid
 * @returns {number} Drop index clamped to [0, totalItems]
 */
function calcGridDropIndex(x, y, cellWidth, cellHeight, cols, totalItems) {
    if (cellWidth <= 0 || cellHeight <= 0 || cols <= 0) return 0;
    let col = Math.floor(x / cellWidth);
    let row = Math.floor(y / cellHeight);
    let index = row * cols + col;
    return Math.max(0, Math.min(index, totalItems));
}

// Export for Node.js testing; ignored in GJS runtime
if (typeof module !== 'undefined' && module.exports) {
    module.exports = {
        calcLauncherIconSize, calcNeededRows, calcContainerColumns, calcContainerWidth, calcVisibleLauncherCount, calcGridDropIndex
    };
}
