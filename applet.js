const Applet = imports.ui.applet;
const AppletManager = imports.ui.appletManager;
const Clutter = imports.gi.Clutter;
const St = imports.gi.St;
const Cinnamon = imports.gi.Cinnamon;
const CMenu = imports.gi.CMenu;
const Lang = imports.lang;
const Gio = imports.gi.Gio;
const PopupMenu = imports.ui.popupMenu;
const Main = imports.ui.main;
const GLib = imports.gi.GLib;
const Tooltips = imports.ui.tooltips;
const DND = imports.ui.dnd;
const Tweener = imports.ui.tweener;
const Util = imports.misc.util;
const Settings = imports.ui.settings;
const Signals = imports.signals;
const SignalManager = imports.misc.signalManager;

const Helpers = require('./helpers');

const PANEL_EDIT_MODE_KEY = 'panel-edit-mode';
const PANEL_LAUNCHERS_KEY = 'panel-launchers';

const CUSTOM_LAUNCHERS_PATH = GLib.get_user_data_dir() + "/cinnamon/panel-launchers/";
const OLD_CUSTOM_LAUNCHERS_PATH = GLib.get_home_dir() + '/.cinnamon/panel-launchers/';

let pressLauncher = null;

class PanelAppLauncherMenu extends Applet.AppletPopupMenu {
    constructor(launcher, orientation) {
        super(launcher, orientation);
        this._launcher = launcher;

        let appinfo = this._launcher.getAppInfo();

        this._actions = appinfo.list_actions();
        if (this._actions.length > 0) {
            for (let i = 0; i < this._actions.length; i++) {
                let actionName = this._actions[i];
                this.addAction(appinfo.get_action_name(actionName), Lang.bind(this, this._launchAction, actionName));
            }

            this.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());
        }

        let item = new PopupMenu.PopupIconMenuItem(_("Launch"), "media-playback-start", St.IconType.SYMBOLIC);
        this._signals.connect(item, 'activate', Lang.bind(this, this._onLaunchActivate));
        this.addMenuItem(item);

        if (Main.gpu_offload_supported) {
            let item = new PopupMenu.PopupIconMenuItem(_("Run with dedicated GPU"), "cpu", St.IconType.SYMBOLIC);
            this._signals.connect(item, 'activate', Lang.bind(this, this._onLaunchOffloadedActivate));
            this.addMenuItem(item);
        }

        item = new PopupMenu.PopupIconMenuItem(_("Add"), "list-add", St.IconType.SYMBOLIC);
        this._signals.connect(item, 'activate', Lang.bind(this, this._onAddActivate));
        this.addMenuItem(item);

        item = new PopupMenu.PopupIconMenuItem(_("Edit"), "document-properties", St.IconType.SYMBOLIC);
        this._signals.connect(item, 'activate', Lang.bind(this, this._onEditActivate));
        this.addMenuItem(item);

        item = new PopupMenu.PopupIconMenuItem(_("Remove"), "window-close", St.IconType.SYMBOLIC);
        this._signals.connect(item, 'activate', Lang.bind(this, this._onRemoveActivate));
        this.addMenuItem(item);

        this.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        let subMenu = new PopupMenu.PopupSubMenuMenuItem(_("Applet preferences"));
        this.addMenuItem(subMenu);

        item = new PopupMenu.PopupIconMenuItem(_("About..."), "dialog-question", St.IconType.SYMBOLIC);
        this._signals.connect(item, 'activate', Lang.bind(this._launcher.launchersBox, this._launcher.launchersBox.openAbout));
        subMenu.menu.addMenuItem(item);

        item = new PopupMenu.PopupIconMenuItem(_("Configure..."), "system-run", St.IconType.SYMBOLIC);
        this._signals.connect(item, 'activate', Lang.bind(this._launcher.launchersBox, this._launcher.launchersBox.configureApplet));
        subMenu.menu.addMenuItem(item);

        this.remove_item = new PopupMenu.PopupIconMenuItem(_("Remove '%s'").format(_("Multi-Row Panel Launchers")), "edit-delete", St.IconType.SYMBOLIC);
        subMenu.menu.addMenuItem(this.remove_item);
    }

    _onLaunchActivate(item, event) {
        this._launcher.launch();
    }

    _onLaunchOffloadedActivate(item, event) {
        this._launcher.launch(true);
    }

    _onRemoveActivate(item, event) {
        this.close();
        this._launcher.launchersBox.removeLauncher(this._launcher, this._launcher.isCustom());
    }

    _onAddActivate(item, event) {
        this._launcher.launchersBox.showAddLauncherDialog(event.get_time());
    }

    _onEditActivate(item, event) {
        this._launcher.launchersBox.showAddLauncherDialog(event.get_time(), this._launcher);
    }

    _launchAction(event, name) {
        this._launcher.launchAction(name);
    }
}

class PanelAppLauncher extends DND.LauncherDraggable {
    constructor(launchersBox, app, appinfo, orientation, icon_size) {
        super(launchersBox);
        this.app = app;
        this.appinfo = appinfo;
        this.orientation = orientation;
        this.icon_size = icon_size;

        this._signals = new SignalManager.SignalManager(null);

        this.actor = new St.Bin({ style_class: 'launcher',
                                  important: true,
                                  reactive: true,
                                  can_focus: true,
                                  x_fill: true,
                                  y_fill: true,
                                  track_hover: true });

        this.actor.set_easing_mode(Clutter.AnimationMode.EASE_IN_QUAD);
        this.actor.set_easing_duration(100);

        this.actor._delegate = this;
        this._signals.connect(this.actor, 'button-release-event', Lang.bind(this, this._onButtonRelease));
        this._signals.connect(this.actor, 'button-press-event', Lang.bind(this, this._onButtonPress));

        this._iconBox = new St.Bin({ style_class: 'icon-box',
                                     important: true });

        this.actor.add_actor(this._iconBox);
        this._iconBottomClip = 0;

        this.icon = this._getIconActor();
        this._iconBox.set_child(this.icon);

        this._signals.connect(this._iconBox, 'style-changed',
                              Lang.bind(this, this._updateIconSize));
        this._signals.connect(this._iconBox, 'notify::allocation',
                              Lang.bind(this, this._updateIconSize));

        this._menuManager = new PopupMenu.PopupMenuManager(this);
        this._menu = new PanelAppLauncherMenu(this, orientation);
        this._signals.connect(this._menu.remove_item, 'activate', (actor, event) => launchersBox.confirmRemoveApplet(event));

        this._menuManager.addMenu(this._menu);

        let tooltipText = this.isCustom() ? appinfo.get_name() : app.get_name();
        this._tooltip = new Tooltips.PanelItemTooltip(this, tooltipText, orientation);

        this._dragging = false;
        this._draggable = DND.makeDraggable(this.actor);

        this._signals.connect(this._draggable, 'drag-begin', Lang.bind(this, this._onDragBegin));
        this._signals.connect(this._draggable, 'drag-end', Lang.bind(this, this._onDragEnd));

        this._updateInhibit();
        this._signals.connect(this.launchersBox, 'launcher-draggable-setting-changed', Lang.bind(this, this._updateInhibit));
        this._signals.connect(global.settings, 'changed::' + PANEL_EDIT_MODE_KEY, Lang.bind(this, this._updateInhibit));
    }

    _onDragBegin() {
        this._dragging = true;
        this._tooltip.hide();
        this._tooltip.preventShow = true;
        this.actor.set_hover(false);
    }

    _onDragEnd(source, time, success) {
        this._dragging = false;
        this._tooltip.preventShow = false;
        this.actor.sync_hover();
        if (!success)
            this.launchersBox._clearDragPlaceholder();
    }

    _updateInhibit() {
        let editMode = global.settings.get_boolean(PANEL_EDIT_MODE_KEY);
        this._draggable.inhibit = !this.launchersBox.allowDragging || editMode;
        this.actor.reactive = !editMode;
    }

    getDragActor() {
        return this._getIconActor();
    }

    getDragActorSource() {
        return this.icon;
    }

    _getIconActor() {
        if (this.isCustom()) {
            let icon = this.appinfo.get_icon();
            if (icon == null)
                icon = new Gio.ThemedIcon({name: "gnome-panel-launcher"});
            return new St.Icon({gicon: icon, icon_size: this.icon_size, icon_type: St.IconType.FULLCOLOR});
        } else {
            return this.app.create_icon_texture(this.icon_size);
        }
    }

    _animateIcon(step) {
        if (step >= 3) return;
        this.icon.set_pivot_point(0.5, 0.5);
        Tweener.addTween(this.icon,
                         { scale_x: 0.7,
                           scale_y: 0.7,
                           time: 0.2,
                           transition: 'easeOutQuad',
                           onComplete() {
                               Tweener.addTween(this.icon,
                                                { scale_x: 1.0,
                                                  scale_y: 1.0,
                                                  time: 0.2,
                                                  transition: 'easeOutQuad',
                                                  onComplete() {
                                                      this._animateIcon(step + 1);
                                                  },
                                                  onCompleteScope: this
                                                });
                           },
                           onCompleteScope: this
                         });
    }

    launch(offload=false) {
        if (this.isCustom()) {
            this.appinfo.launch([], null);
        } else {
            if (offload) {
                try {
                    this.app.launch_offloaded(0, [], -1);
                } catch (e) {
                    logError(e, "Could not launch app with dedicated gpu: ");
                }
            } else {
                this.app.open_new_window(-1);
            }
        }
        this._animateIcon(0);
    }

    launchAction(name) {
        this.getAppInfo().launch_action(name, null);
        this._animateIcon(0);
    }

    getId() {
        if (this.isCustom()) return Gio.file_new_for_path(this.appinfo.get_filename()).get_basename();
        else return this.app.get_id();
    }

    isCustom() {
        return (this.app==null);
    }

    _onButtonPress(actor, event) {
        pressLauncher = this.getAppname();

        if (event.get_button() == 3)
            this._menu.toggle();
    }

    _onButtonRelease(actor, event) {
        if (pressLauncher == this.getAppname()){
            let button = event.get_button();
            if (button==1) {
                if (this._menu.isOpen) this._menu.toggle();
                else this.launch();
            }
        }
    }

    _updateIconSize() {
        let node = this._iconBox.get_theme_node();
        let enforcedSize = 0;

        if (this._iconBox.height > 0) {
            enforcedSize = this._iconBox.height - node.get_vertical_padding();
        }
        else
        if (this._iconBox.width > 0) {
            enforcedSize = this._iconBox.width - node.get_horizontal_padding();
        }
        else
        {
            enforcedSize = -1;
        }

        if (enforcedSize < this.icon.get_icon_size()) {
            this.icon.set_icon_size(enforcedSize);
        }
    }

    getAppInfo() {
        return (this.isCustom() ? this.appinfo : this.app.get_app_info());
    }

    getCommand() {
        return this.getAppInfo().get_commandline();
    }

    getAppname() {
        return this.getAppInfo().get_name();
    }

    getIcon() {
        let icon = this.getAppInfo().get_icon();
        if (icon) {
            if (icon instanceof Gio.FileIcon) {
                return icon.get_file().get_path();
            }
            else {
                return icon.get_names().toString();
            }
        }
        return null;
    }

    destroy() {
        this._signals.disconnectAllSignals();
        this._menu.destroy();
        this._menuManager.destroy();
        this.actor.destroy();
    }
}

// LaunchersBox: holds launchers and handles DND.
// Uses Clutter.Actor + FlowLayout for horizontal panels to support multi-row wrapping.
// DND methods receive event coords pre-transformed to actor-relative.
class LaunchersBox {
    constructor(applet, orientation) {
        let isHorizontal = (orientation == St.Side.TOP || orientation == St.Side.BOTTOM);

        let manager;
        if (isHorizontal) {
            manager = new Clutter.FlowLayout({
                orientation: Clutter.FlowOrientation.HORIZONTAL,
                homogeneous: true,
                column_spacing: 2,
                row_spacing: 0
            });
        } else {
            manager = new Clutter.BoxLayout({ orientation: Clutter.Orientation.VERTICAL });
        }

        this.manager = manager;
        this.actor = new Clutter.Actor({ layout_manager: manager });
        this.actor._delegate = this;
        this.actor.connect("destroy", () => this._destroy());

        // Override FlowLayout's inflated min_width so the panel's _calcBoxSizes()
        // enters the proportional-sharing branch instead of squeezing panel zones.
        if (isHorizontal) {
            this.actor.min_width = 0;
        }

        this.applet = applet;
        this._dragPlaceholder = null;
        this._dragTargetIndex = null;
        this._dragLocalOriginInfo = null;
    }

    _clearDragPlaceholder(skipAnimation=false) {
        if (this._dragLocalOriginInfo != null) {
            this.actor.set_child_at_index(this._dragLocalOriginInfo.actor, this._dragLocalOriginInfo.index);
        }

        if (this._dragPlaceholder) {
            if (skipAnimation) {
                this._dragPlaceholder.actor.destroy();
            } else {
                this._dragPlaceholder.animateOutAndDestroy();
            }
        }

        this._dragPlaceholder = null;
        this._dragLocalOriginInfo = null;
        this._dragTargetIndex = null;
    }

    // 2D DND: find closest child using Euclidean distance to allocation centers.
    // Internal reorder only — no external drops from app menus.
    handleDragOver(source, actor, x, y, time) {
        if (!(source instanceof DND.LauncherDraggable)) {
            return DND.DragMotionResult.NO_DROP;
        }

        let originalIndex = this.applet._launchers.indexOf(source);
        let children = this.actor.get_children();

        // Find closest child by Euclidean distance to allocation center
        let dropIndex = 0;
        let minDist = -1;
        for (let i = 0; i < children.length; i++) {
            if (!children[i].visible) continue;
            let alloc = children[i].get_allocation_box();
            let cx = (alloc.x1 + alloc.x2) / 2;
            let cy = (alloc.y1 + alloc.y2) / 2;
            let dist = Math.sqrt((x - cx) * (x - cx) + (y - cy) * (y - cy));
            if (dist < minDist || minDist === -1) {
                minDist = dist;
                dropIndex = i;
            }
        }

        if (dropIndex >= children.length)
            dropIndex = -1;

        if (this._dragTargetIndex != dropIndex) {
            if (originalIndex > -1) {
                // Local drag — move source actor directly
                if (!this._dragLocalOriginInfo)
                    this._dragLocalOriginInfo = { actor: source.actor, index: originalIndex };
                this.actor.set_child_at_index(source.actor, dropIndex);
                this._dragTargetIndex = dropIndex;
            }
        }

        return DND.DragMotionResult.MOVE_DROP;
    }

    handleDragOut() {
        this._clearDragPlaceholder();
    }

    // Internal reorder only — source must be one of our launchers
    acceptDrop(source, actor, x, y, time) {
        if (!(source instanceof DND.LauncherDraggable)) {
            this._clearDragPlaceholder(true);
            return false;
        }

        if (this._dragTargetIndex == null) {
            this._clearDragPlaceholder(true);
            return false;
        }

        let dropIndex = this._dragTargetIndex;
        this._clearDragPlaceholder(true);

        if (this.applet._launchers.indexOf(source) != -1) {
            this.applet._reinsertAtIndex(source, dropIndex);
        }

        return true;
    }

    _destroy() {
        this.actor._delegate = null;
        this.actor = null;
        this.applet = null;
    }
}

class CinnamonPanelLaunchersApplet extends Applet.Applet {
    constructor(metadata, orientation, panel_height, instance_id) {
        super(orientation, panel_height, instance_id);
        this.actor.set_track_hover(false);

        this.setAllowedLayout(Applet.AllowedLayout.BOTH);

        this.orientation = orientation;

        this.signals = new SignalManager.SignalManager(null);

        this.launchersBox = new LaunchersBox(this, orientation);
        this.myactor = this.launchersBox.actor;

        this.settings = new Settings.AppletSettings(this, "multirow-panel-launchers@cinnamon", instance_id);
        this.settings.bind("launcherList", "launcherList", this._reload);
        this.settings.bind("allow-dragging", "allowDragging", this._updateLauncherDrag);
        this.settings.bind("max-rows", "maxRows", this._onLayoutSettingsChanged);
        this.settings.bind("icon-size-override", "iconSizeOverride", this._onLayoutSettingsChanged);

        this.uuid = metadata.uuid;

        this._settings_proxy = [];
        this._launchers = [];
        this._inAllocationUpdate = false;

        this.actor.add(this.myactor);
        this.actor.reactive = global.settings.get_boolean(PANEL_EDIT_MODE_KEY);
        global.settings.connect('changed::' + PANEL_EDIT_MODE_KEY, Lang.bind(this, this._onPanelEditModeChanged));

        // FlowLayout needs a width constraint to trigger wrapping.
        if (this.orientation == St.Side.TOP || this.orientation == St.Side.BOTTOM) {
            this.signals.connect(this.actor, 'notify::allocation', this._onAllocationChanged, this);
        }

        this._recalcIconSize();

        this.do_gsettings_import();

        this.on_orientation_changed(orientation);
    }

    _recalcIconSize() {
        let panelHeight = this._panelHeight || 25;
        let rows = this.maxRows || 2;
        let override = this.iconSizeOverride || 0;
        this.icon_size = Helpers.calcLauncherIconSize(panelHeight, rows, override);
    }

    _onLayoutSettingsChanged() {
        this._recalcIconSize();
        this._reload();
    }

    _onAllocationChanged() {
        if (this._inAllocationUpdate) return;
        this._inAllocationUpdate = true;
        try {
            let allocBox = this.actor.get_allocation_box();
            let width = allocBox.x2 - allocBox.x1;
            if (width > 0) {
                this.myactor.set_width(width);
                this.myactor.min_width = 0;
            }
        } finally {
            this._inAllocationUpdate = false;
        }
    }

    _updateLauncherDrag() {
        this.emit("launcher-draggable-setting-changed");
    }

    do_gsettings_import() {
        let old_launchers = global.settings.get_strv(PANEL_LAUNCHERS_KEY);
        if (old_launchers.length >= 1 && old_launchers[0] != "DEPRECATED") {
            this.launcherList = old_launchers;
        }

        global.settings.set_strv(PANEL_LAUNCHERS_KEY, ["DEPRECATED"]);
    }

    _onPanelEditModeChanged() {
        this.actor.reactive = global.settings.get_boolean(PANEL_EDIT_MODE_KEY);
    }

    sync_settings_proxy_to_settings() {
        this.settings.unbind("launcherList");
        this.launcherList = this._settings_proxy.map(x => x.file);
        this.settings.setValue("launcherList", this.launcherList);
        this.settings.bind("launcherList", "launcherList", this._reload);
    }

    _remove_launcher_from_proxy(visible_index) {
        let j = -1;
        for (let i = 0; i < this._settings_proxy.length; i++) {
            if (this._settings_proxy[i].valid) {
                j++;
                if (j == visible_index) {
                    this._settings_proxy.splice(i, 1);
                    break;
                }
            }
        }
    }

    _move_launcher_in_proxy(launcher, new_index) {
        let proxy_member;
        for (let i = 0; i < this._settings_proxy.length; i++) {
            if (this._settings_proxy[i].launcher == launcher) {
                proxy_member = this._settings_proxy.splice(i, 1)[0];
                break;
            }
        }

        if (!proxy_member)
            return;

        this._insert_proxy_member(proxy_member, new_index);
    }

    _insert_proxy_member(member, visible_index) {
        if (visible_index == -1) {
            this._settings_proxy.push(member);
            return;
        }

        let j = -1;
        for (let i = 0; i < this._settings_proxy.length; i++) {
            if (this._settings_proxy[i].valid) {
                j++;
                if (j == visible_index) {
                    this._settings_proxy.splice(i, 0, member);
                    return;
                }
            }
        }

        if (visible_index == j + 1)
            this._settings_proxy.push(member);
    }

    _loadLauncher(path) {
        let appSys = Cinnamon.AppSystem.get_default();
        let app = appSys.lookup_app(path);
        let appinfo = null;
        if (!app) {
            appinfo = CMenu.DesktopAppInfo.new_from_filename(CUSTOM_LAUNCHERS_PATH + path);
            if (!appinfo) {
                appinfo = CMenu.DesktopAppInfo.new_from_filename(OLD_CUSTOM_LAUNCHERS_PATH + path);
            }
            if (!appinfo) {
                global.logWarning(`Failed to add launcher from path: ${path}`);
                return null;
            }
        }
        return new PanelAppLauncher(this, app, appinfo, this.orientation, this.icon_size);
    }

    on_panel_height_changed() {
        this._recalcIconSize();
        this._reload();
    }

    on_panel_icon_size_changed(size) {
        this.icon_size = size;
        this._reload();
    }

    on_orientation_changed(neworientation) {
        this.orientation = neworientation;
        let isHorizontal = (neworientation == St.Side.TOP || neworientation == St.Side.BOTTOM);

        if (isHorizontal) {
            let manager = new Clutter.FlowLayout({
                orientation: Clutter.FlowOrientation.HORIZONTAL,
                homogeneous: true,
                column_spacing: 2,
                row_spacing: 0
            });
            this.launchersBox.manager = manager;
            this.myactor.set_layout_manager(manager);
            this.myactor.min_width = 0;
            this.myactor.remove_style_class_name('vertical');

            // Re-add the allocation listener (disconnect first to avoid duplicates)
            this.signals.disconnect('notify::allocation', this.actor);
            this.signals.connect(this.actor, 'notify::allocation', this._onAllocationChanged, this);
        } else {
            let manager = new Clutter.BoxLayout({ orientation: Clutter.Orientation.VERTICAL });
            this.launchersBox.manager = manager;
            this.myactor.set_layout_manager(manager);
            this.myactor.add_style_class_name('vertical');

            // Remove allocation listener and width constraint for vertical
            this.signals.disconnect('notify::allocation', this.actor);
            this.myactor.set_width(-1);
            this.myactor.min_width = -1;
        }

        this._reload();
    }

    _reload() {
        this._launchers.forEach(l => l.destroy());
        this._launchers = [];
        this._settings_proxy = [];

        for (let file of this.launcherList) {
            let launcher = this._loadLauncher(file);
            let proxyObj = { file: file, valid: false, launcher: null };
            if (launcher) {
                this.myactor.add_actor(launcher.actor);
                this._launchers.push(launcher);
                proxyObj.valid = true;
                proxyObj.launcher = launcher;
            }
            this._settings_proxy.push(proxyObj);
        }
    }

    removeLauncher(launcher, delete_file) {
        let i = this._launchers.indexOf(launcher);
        if (i >= 0) {
            launcher.destroy();
            this._launchers.splice(i, 1);
            this._remove_launcher_from_proxy(i);
        }
        if (delete_file) {
            let appid = launcher.getId();
            let file = Gio.file_new_for_path(CUSTOM_LAUNCHERS_PATH + appid);
            if (file.query_exists(null)) file.delete(null);
            let old_file = Gio.file_new_for_path(OLD_CUSTOM_LAUNCHERS_PATH + appid);
            if (old_file.query_exists(null)) old_file.delete(null);
        }

        this.sync_settings_proxy_to_settings();
    }

    // Called by the Cinnamon menu's "Add to Panel" when this applet holds
    // the panellauncher role. Adds a new launcher via settings reload path.
    acceptNewLauncher(path) {
        let newLauncher = this._loadLauncher(path);
        if (!newLauncher)
            return;

        this.myactor.add_actor(newLauncher.actor);
        this._launchers.push(newLauncher);
        this._insert_proxy_member({ file: path, valid: true, launcher: newLauncher }, -1);
        this.sync_settings_proxy_to_settings();
    }

    showAddLauncherDialog(timestamp, launcher){
        if (launcher) {
            Util.spawnCommandLine("cinnamon-desktop-editor -mcinnamon-launcher --icon-size %d -f %s %s"
                .format(this.icon_size, launcher.getId(), this.settings.file.get_path()));
        } else {
            Util.spawnCommandLine("cinnamon-desktop-editor -mcinnamon-launcher --icon-size %d %s"
                .format(this.icon_size, this.settings.file.get_path()))
        }
    }

    _reinsertAtIndex(launcher, newIndex) {
        let originalIndex = this._launchers.indexOf(launcher);
        if (originalIndex == -1)
            return;

        if (originalIndex != newIndex) {
            this.myactor.set_child_at_index(launcher.actor, newIndex);
            this._launchers.splice(originalIndex, 1);
            this._launchers.splice(newIndex, 0, launcher);
            this._move_launcher_in_proxy(launcher, newIndex);
            this.sync_settings_proxy_to_settings();
        }
    }

    _clearDragPlaceholder(skipAnimation=false) {
        this.launchersBox._clearDragPlaceholder(skipAnimation);
    }

    on_applet_removed_from_panel() {
        this._launchers.forEach(l => l.destroy());
        this._launchers = [];
        this.signals.disconnectAllSignals();
    }
}
Signals.addSignalMethods(CinnamonPanelLaunchersApplet.prototype);

function main(metadata, orientation, panel_height, instance_id) {
    return new CinnamonPanelLaunchersApplet(metadata, orientation, panel_height, instance_id);
}
