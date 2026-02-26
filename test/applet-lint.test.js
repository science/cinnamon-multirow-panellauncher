const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const appletSource = fs.readFileSync(path.join(ROOT, 'applet.js'), 'utf8');
const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'metadata.json'), 'utf8'));

describe('applet.js safety checks', () => {
    describe('cleanup on removal', () => {
        it('has on_applet_removed_from_panel method', () => {
            assert.ok(
                appletSource.includes('on_applet_removed_from_panel'),
                'missing on_applet_removed_from_panel method'
            );
        });

        it('destroys launchers in on_applet_removed_from_panel', () => {
            const methodMatch = appletSource.match(
                /on_applet_removed_from_panel\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find on_applet_removed_from_panel body');
            const body = methodMatch[1];

            assert.ok(
                body.includes('.destroy()'),
                'on_applet_removed_from_panel must call .destroy() on launchers'
            );
            assert.ok(
                body.includes('this._launchers'),
                'on_applet_removed_from_panel must reference this._launchers'
            );
        });

        it('calls signals.disconnectAllSignals in cleanup', () => {
            const methodMatch = appletSource.match(
                /on_applet_removed_from_panel\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch);
            const body = methodMatch[1];
            assert.ok(
                body.includes('disconnectAllSignals'),
                'on_applet_removed_from_panel must call signals.disconnectAllSignals()'
            );
        });
    });

    describe('settings UUID', () => {
        it('uses the correct UUID from metadata.json', () => {
            const uuid = metadata.uuid;
            const settingsPattern = new RegExp(
                `new Settings\\.AppletSettings\\(this,\\s*"${uuid.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}"`
            );
            assert.ok(
                settingsPattern.test(appletSource),
                `applet.js must use Settings UUID "${uuid}" matching metadata.json`
            );
        });
    });

    describe('metadata.json', () => {
        it('does not have forbidden "icon" field', () => {
            assert.ok(
                !('icon' in metadata),
                'metadata.json must not have "icon" field (forbidden by Spices; use icon.png instead)'
            );
        });

        it('does not have forbidden "dangerous" field', () => {
            assert.ok(
                !('dangerous' in metadata),
                'metadata.json must not have "dangerous" field (forbidden by Spices)'
            );
        });

        it('does not have forbidden "last-edited" field', () => {
            assert.ok(
                !('last-edited' in metadata),
                'metadata.json must not have "last-edited" field (forbidden by Spices)'
            );
        });
    });

    describe('signal cleanup', () => {
        it('routes global.settings.connect through SignalManager', () => {
            // Bare global.settings.connect() leaks — must use this.signals.connect(global.settings, ...)
            assert.ok(
                !appletSource.includes("global.settings.connect("),
                'must not use bare global.settings.connect() — route through this.signals.connect(global.settings, ...) for cleanup'
            );
        });
    });

    describe('FlowLayout container', () => {
        it('uses Clutter.FlowLayout for horizontal panels', () => {
            assert.ok(
                appletSource.includes('Clutter.FlowLayout'),
                'must use Clutter.FlowLayout'
            );
        });

        it('uses Clutter.Actor with layout_manager (not St.BoxLayout)', () => {
            // The main container should be a Clutter.Actor with layout_manager, not St.BoxLayout
            assert.ok(
                appletSource.includes('new Clutter.Actor'),
                'must use Clutter.Actor for layout container'
            );
        });

        it('sets min_width = 0 on manager_container for horizontal panels', () => {
            assert.ok(
                appletSource.includes('min_width = 0'),
                'must set min_width = 0 to prevent panel zone squeeze'
            );
        });
    });

    describe('allocation listener', () => {
        it('has _onAllocationChanged method', () => {
            assert.ok(
                appletSource.includes('_onAllocationChanged'),
                'must have _onAllocationChanged method'
            );
        });

        it('has _updateContainerWidth that sets content-based width', () => {
            assert.ok(
                appletSource.includes('_updateContainerWidth'),
                'must have _updateContainerWidth method'
            );
            const methodMatch = appletSource.match(
                /_updateContainerWidth\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _updateContainerWidth body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('set_width'),
                '_updateContainerWidth must call set_width with content-based width'
            );
            assert.ok(
                body.includes('_getCellWidth'),
                '_updateContainerWidth must use _getCellWidth for cell width query'
            );
        });

        it('_getCellWidth queries get_preferred_width', () => {
            const methodMatch = appletSource.match(
                /_getCellWidth\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _getCellWidth body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('get_preferred_width'),
                '_getCellWidth must query get_preferred_width for content width'
            );
        });

        it('has re-entrancy guard in _onAllocationChanged', () => {
            const methodMatch = appletSource.match(
                /_onAllocationChanged\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch);
            const body = methodMatch[1];
            assert.ok(
                body.includes('_inAllocationUpdate'),
                '_onAllocationChanged must use _inAllocationUpdate re-entrancy guard'
            );
        });

        it('re-asserts min_width = 0 in _onAllocationChanged', () => {
            const methodMatch = appletSource.match(
                /_onAllocationChanged\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch);
            const body = methodMatch[1];
            assert.ok(
                body.includes('min_width = 0'),
                '_onAllocationChanged must re-assert min_width = 0'
            );
        });

        it('calls _updateContainerWidth from _onAllocationChanged', () => {
            const methodMatch = appletSource.match(
                /_onAllocationChanged\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch);
            const body = methodMatch[1];
            assert.ok(
                body.includes('_updateContainerWidth'),
                '_onAllocationChanged must call _updateContainerWidth to correct sizing after children are styled'
            );
        });
    });

    describe('orientation handling', () => {
        it('has on_orientation_changed method', () => {
            assert.ok(
                appletSource.includes('on_orientation_changed'),
                'must have on_orientation_changed'
            );
        });

        it('creates FlowLayout and sets layout_manager in on_orientation_changed', () => {
            // After on_orientation_changed, the source should show FlowLayout creation
            // and set_layout_manager call in the same method
            const afterMethod = appletSource.substring(
                appletSource.indexOf('on_orientation_changed')
            );
            // Grab up to the next method definition (4-space indented identifier followed by ()
            const nextMethod = afterMethod.indexOf('\n    _reload');
            const body = nextMethod > 0 ? afterMethod.substring(0, nextMethod) : afterMethod;
            assert.ok(
                body.includes('FlowLayout'),
                'on_orientation_changed must create FlowLayout for horizontal'
            );
            assert.ok(
                body.includes('set_layout_manager'),
                'on_orientation_changed must call set_layout_manager'
            );
        });
    });

    describe('icon sizing', () => {
        it('imports helpers.js', () => {
            assert.ok(
                appletSource.includes("require('./helpers')") || appletSource.includes('require("./helpers")'),
                'must import helpers.js'
            );
        });

        it('calls calcLauncherIconSize', () => {
            assert.ok(
                appletSource.includes('calcLauncherIconSize'),
                'must use calcLauncherIconSize from helpers'
            );
        });

        it('calls calcContainerWidth for width calculation', () => {
            assert.ok(
                appletSource.includes('calcContainerWidth'),
                'must use calcContainerWidth from helpers for container width'
            );
        });
    });

    describe('on_panel_icon_size_changed', () => {
        it('uses _recalcIconSize instead of raw assignment', () => {
            const methodMatch = appletSource.match(
                /on_panel_icon_size_changed\s*\([^)]*\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find on_panel_icon_size_changed body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('_recalcIconSize'),
                'on_panel_icon_size_changed must use _recalcIconSize() for multi-row calculation'
            );
            assert.ok(
                !body.includes('this.icon_size = size') && !body.includes('this.icon_size=size'),
                'on_panel_icon_size_changed must not directly assign this.icon_size = size'
            );
        });
    });

    describe('_updateIconSize guard', () => {
        it('does not set icon_size to negative values', () => {
            const methodMatch = appletSource.match(
                /_updateIconSize\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _updateIconSize body');
            const body = methodMatch[1];
            // Must not contain the raw "enforcedSize = -1" pattern
            assert.ok(
                !body.includes('enforcedSize = -1'),
                '_updateIconSize must not set enforcedSize to -1 (bail out on invalid allocation instead)'
            );
        });
    });

    describe('width calculation', () => {
        it('_updateContainerWidth uses calcContainerWidth from helpers', () => {
            const methodMatch = appletSource.match(
                /_updateContainerWidth\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _updateContainerWidth body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('calcContainerWidth'),
                '_updateContainerWidth must use Helpers.calcContainerWidth for exact width math'
            );
        });

        it('container has clip_to_allocation for overflow safety', () => {
            assert.ok(
                appletSource.includes('clip_to_allocation'),
                'FlowLayout container must set clip_to_allocation as overflow safety net'
            );
        });
    });

    describe('DND', () => {
        it('only accepts LauncherDraggable sources (no isDraggableApp)', () => {
            // handleDragOver should not accept isDraggableApp
            const methodMatch = appletSource.match(
                /handleDragOver\s*\([\s\S]*?\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find handleDragOver body');
            const body = methodMatch[1];
            assert.ok(
                !body.includes('isDraggableApp'),
                'handleDragOver must not accept isDraggableApp (internal reorder only)'
            );
        });
    });

    describe('acceptNewLauncher', () => {
        it('has acceptNewLauncher method for panel role', () => {
            assert.ok(
                appletSource.includes('acceptNewLauncher'),
                'must have acceptNewLauncher for panellauncher role'
            );
        });
    });

    describe('hover/click feedback', () => {
        it('has _connectHoverFeedback method (not overflow-specific)', () => {
            assert.ok(
                appletSource.includes('_connectHoverFeedback'),
                'must have _connectHoverFeedback method for all launchers'
            );
        });

        it('has _disconnectHoverFeedback method', () => {
            assert.ok(
                appletSource.includes('_disconnectHoverFeedback'),
                'must have _disconnectHoverFeedback method'
            );
        });

        it('connects hover feedback to ALL launchers in _redistributeLaunchers', () => {
            const methodMatch = appletSource.match(
                /_redistributeLaunchers\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _redistributeLaunchers body');
            const body = methodMatch[1];
            // Both branches (no-overflow and overflow) must connect hover
            const connectCalls = (body.match(/_connectHoverFeedback/g) || []).length;
            assert.ok(
                connectCalls >= 2,
                '_redistributeLaunchers must call _connectHoverFeedback in both branches (panel and overflow)'
            );
        });

        it('does not use overflow-specific hover method names', () => {
            assert.ok(
                !appletSource.includes('_connectOverflowHover'),
                'must not use old _connectOverflowHover name (hover applies to all launchers)'
            );
            assert.ok(
                !appletSource.includes('_disconnectOverflowHover'),
                'must not use old _disconnectOverflowHover name'
            );
        });
    });

    describe('overflow popup', () => {
        it('destroys overflow UI in on_applet_removed_from_panel', () => {
            const methodMatch = appletSource.match(
                /on_applet_removed_from_panel\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find on_applet_removed_from_panel body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('_destroyOverflowUI'),
                'on_applet_removed_from_panel must call _destroyOverflowUI'
            );
        });

        it('does not use AppletPopupMenu for overflow', () => {
            // _ensureOverflowUI should NOT create an AppletPopupMenu
            const methodMatch = appletSource.match(
                /_ensureOverflowUI\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _ensureOverflowUI body');
            const body = methodMatch[1];
            assert.ok(
                !body.includes('AppletPopupMenu'),
                '_ensureOverflowUI must not use AppletPopupMenu (causes DND conflict via pushModal)'
            );
        });

        it('adds overflow panel to global.stage (above top_window_group)', () => {
            const methodMatch = appletSource.match(
                /_ensureOverflowUI\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _ensureOverflowUI body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('global.stage'),
                '_ensureOverflowUI must add overflow panel to global.stage for correct paint/pick order'
            );
        });

        it('uses captured-event for click-outside detection', () => {
            assert.ok(
                appletSource.includes('captured-event'),
                'must use captured-event on global.stage for click-outside detection'
            );
        });

        it('uses pushModal/popModal for input routing', () => {
            assert.ok(
                appletSource.includes('pushModal'),
                'must use pushModal to route input through Clutter stage'
            );
            assert.ok(
                appletSource.includes('popModal'),
                'must use popModal when closing overflow panel'
            );
        });

        it('adds chevron to this.actor (not myactor)', () => {
            const methodMatch = appletSource.match(
                /_ensureOverflowUI\s*\(\)\s*\{([\s\S]*?)^\s{4}\}/m
            );
            assert.ok(methodMatch, 'could not find _ensureOverflowUI body');
            const body = methodMatch[1];
            assert.ok(
                body.includes('this.actor.add'),
                '_ensureOverflowUI must add chevron to this.actor (applet-box), not myactor'
            );
        });

        it('has _redistributeLaunchers method', () => {
            assert.ok(
                appletSource.includes('_redistributeLaunchers'),
                'must have _redistributeLaunchers method'
            );
        });

        it('has _destroyOverflowUI method', () => {
            assert.ok(
                appletSource.includes('_destroyOverflowUI'),
                'must have _destroyOverflowUI method'
            );
        });

        it('has _closeOverflowPanel method', () => {
            assert.ok(
                appletSource.includes('_closeOverflowPanel'),
                'must have _closeOverflowPanel for dismissing overflow'
            );
        });

        it('has _calcOverflowPanelPosition method', () => {
            assert.ok(
                appletSource.includes('_calcOverflowPanelPosition'),
                'must have _calcOverflowPanelPosition for positioning on uiGroup'
            );
        });
    });
});
