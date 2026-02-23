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
        calcLauncherIconSize, calcNeededRows, calcGridDropIndex
    };
}
