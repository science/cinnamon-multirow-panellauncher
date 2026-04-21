const { describe, it, beforeEach, afterEach } = require('node:test');
const assert = require('node:assert/strict');
const { execSync } = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');

const PROJECT_DIR = path.resolve(__dirname, '..');
const UUID = 'multirow-panel-launchers@cinnamon';
const STOCK_UUID = 'panel-launchers@cinnamon.org';

/**
 * Create a sandboxed environment for testing install/uninstall scripts.
 *
 * Sets up:
 *   - A fake HOME with .local/share/cinnamon/applets/
 *   - A mock `cinnamon` binary that reports a version
 *   - A mock `dconf` binary that reads/writes a flat file as a fake dconf store
 *   - PATH with mocks prepended
 */
function createSandbox() {
    const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'applet-test-'));
    const fakeHome = path.join(sandbox, 'home');
    const appletParent = path.join(fakeHome, '.local', 'share', 'cinnamon', 'applets');
    const mockBin = path.join(sandbox, 'bin');
    const dconfStore = path.join(sandbox, 'dconf-store');

    fs.mkdirSync(appletParent, { recursive: true });
    fs.mkdirSync(mockBin, { recursive: true });

    // Mock cinnamon binary
    fs.writeFileSync(path.join(mockBin, 'cinnamon'), `#!/bin/bash
echo "Cinnamon 6.0.4"
`, { mode: 0o755 });

    // Mock dconf binary — uses a flat file as a store
    fs.writeFileSync(path.join(mockBin, 'dconf'), `#!/bin/bash
STORE="${dconfStore}"
if [ "$1" = "read" ]; then
    cat "$STORE" 2>/dev/null || echo ""
elif [ "$1" = "write" ]; then
    shift; shift  # skip 'write' and key
    echo "$@" > "$STORE"
fi
`, { mode: 0o755 });

    return {
        sandbox,
        fakeHome,
        appletParent,
        mockBin,
        dconfStore,
        env: {
            HOME: fakeHome,
            PATH: `${mockBin}:${process.env.PATH}`,
            DBUS_SESSION_BUS_ADDRESS: 'disabled:',
        },
        cleanup() {
            fs.rmSync(sandbox, { recursive: true, force: true });
        }
    };
}

function runScript(scriptName, env, args = '') {
    const script = path.join(PROJECT_DIR, scriptName);
    const argPart = args ? ` ${args}` : '';
    try {
        const output = execSync(`bash "${script}"${argPart} 2>&1`, {
            env: { ...process.env, ...env },
            cwd: PROJECT_DIR,
            timeout: 10000,
        });
        return { code: 0, output: output.toString() };
    } catch (e) {
        return { code: e.status, output: (e.stdout || '').toString() + (e.stderr || '').toString() };
    }
}

// install.sh requires a mode arg (currently only 'dev'); tests always use dev.
function runInstall(env) {
    return runScript('install.sh', env, 'dev');
}

describe('install.sh', { concurrency: 1 }, () => {
    let sb;

    beforeEach(() => {
        sb = createSandbox();
    });

    afterEach(() => {
        sb.cleanup();
    });

    it('creates symlink into applet directory', () => {
        const result = runInstall(sb.env);
        assert.equal(result.code, 0, `install.sh failed: ${result.output}`);

        const appletDir = path.join(sb.appletParent, UUID);
        assert.ok(fs.lstatSync(appletDir).isSymbolicLink(), 'Expected symlink');
        assert.equal(fs.readlinkSync(appletDir), PROJECT_DIR);
    });

    it('reports Cinnamon version', () => {
        const result = runInstall(sb.env);
        assert.match(result.output, /Cinnamon version: 6\.0\.4/);
    });

    it('reports required files OK', () => {
        const result = runInstall(sb.env);
        assert.match(result.output, /Required files: OK/);
    });

    it('reports metadata UUID OK', () => {
        const result = runInstall(sb.env);
        assert.match(result.output, /Metadata UUID: OK/);
    });

    it('is idempotent — skips if symlink already points to repo', () => {
        runInstall(sb.env);
        const result = runInstall(sb.env);
        assert.equal(result.code, 0);
        assert.match(result.output, /already exists and points to this repo/);
    });

    it('warns about stock panel-launchers if present in dconf', () => {
        fs.writeFileSync(sb.dconfStore,
            `['panel1:center:0:${STOCK_UUID}:2']`);

        const result = runInstall(sb.env);
        assert.equal(result.code, 0);
        assert.match(result.output, /Stock panel-launchers/);
        assert.match(result.output, /panellauncher/);
    });

    it('does not warn about stock panel-launchers if absent from dconf', () => {
        fs.writeFileSync(sb.dconfStore, `[]`);

        const result = runInstall(sb.env);
        assert.equal(result.code, 0);
        assert.ok(!result.output.includes('Stock panel-launchers'),
            'Should not warn when stock applet is absent');
    });

    it('fails if cinnamon is not installed', () => {
        const cleanBin = path.join(sb.sandbox, 'clean-bin');
        fs.mkdirSync(cleanBin);
        for (const cmd of ['bash', 'python3', 'grep', 'ln', 'mkdir', 'rm', 'readlink', 'cat', 'dirname', 'basename', 'echo']) {
            try {
                const real = execSync(`which ${cmd} 2>/dev/null`, { encoding: 'utf-8' }).trim();
                if (real) fs.symlinkSync(real, path.join(cleanBin, cmd));
            } catch (e) { /* builtin, skip */ }
        }
        fs.copyFileSync(path.join(sb.mockBin, 'dconf'), path.join(cleanBin, 'dconf'));
        const env = { ...sb.env, PATH: cleanBin };
        const result = runScript('install.sh', env, 'dev');
        assert.notEqual(result.code, 0);
        assert.match(result.output, /cinnamon not found/);
    });

    it('replaces symlink pointing to wrong target', () => {
        const appletDir = path.join(sb.appletParent, UUID);
        fs.symlinkSync('/tmp/wrong-target', appletDir);

        const result = runInstall(sb.env);
        assert.equal(result.code, 0);
        assert.match(result.output, /Removing old symlink/);
        assert.equal(fs.readlinkSync(appletDir), PROJECT_DIR);
    });

    it('fails if a directory install already exists', () => {
        const appletDir = path.join(sb.appletParent, UUID);
        fs.mkdirSync(appletDir, { recursive: true });

        const result = runInstall(sb.env);
        assert.notEqual(result.code, 0);
        assert.match(result.output, /Directory install exists/);
    });

    it('prints uninstall reminder', () => {
        const result = runInstall(sb.env);
        assert.match(result.output, /uninstall\.sh/);
    });
});

describe('uninstall.sh', { concurrency: 1 }, () => {
    let sb;

    beforeEach(() => {
        sb = createSandbox();
    });

    afterEach(() => {
        sb.cleanup();
    });

    it('removes symlink', () => {
        const appletDir = path.join(sb.appletParent, UUID);
        fs.symlinkSync(PROJECT_DIR, appletDir);

        const result = runScript('uninstall.sh', sb.env);
        assert.equal(result.code, 0);
        assert.ok(!fs.existsSync(appletDir), 'Symlink should be removed');
        assert.match(result.output, /Removed symlink/);
    });

    it('removes directory install', () => {
        const appletDir = path.join(sb.appletParent, UUID);
        fs.mkdirSync(appletDir, { recursive: true });
        fs.writeFileSync(path.join(appletDir, 'applet.js'), '// test');

        const result = runScript('uninstall.sh', sb.env);
        assert.equal(result.code, 0);
        assert.ok(!fs.existsSync(appletDir), 'Directory should be removed');
        assert.match(result.output, /Removed directory/);
    });

    it('handles already-removed applet gracefully', () => {
        const result = runScript('uninstall.sh', sb.env);
        assert.equal(result.code, 0);
        assert.match(result.output, /No applet directory found/);
    });

    it('removes UUID from dconf enabled-applets', () => {
        fs.writeFileSync(sb.dconfStore,
            `['panel1:center:0:${STOCK_UUID}:2', 'panel1:center:1:${UUID}:18']`);

        const appletDir = path.join(sb.appletParent, UUID);
        fs.symlinkSync(PROJECT_DIR, appletDir);

        const result = runScript('uninstall.sh', sb.env);
        assert.equal(result.code, 0);
        assert.match(result.output, /Removed from enabled-applets/);

        const stored = fs.readFileSync(sb.dconfStore, 'utf-8');
        assert.ok(!stored.includes(UUID), 'Our UUID should be removed from dconf');
        assert.ok(stored.includes(STOCK_UUID), 'Stock UUID should remain in dconf');
    });

    it('warns if no stock panel-launchers remains after removal', () => {
        fs.writeFileSync(sb.dconfStore,
            `['panel1:center:1:${UUID}:18']`);

        const appletDir = path.join(sb.appletParent, UUID);
        fs.symlinkSync(PROJECT_DIR, appletDir);

        const result = runScript('uninstall.sh', sb.env);
        assert.equal(result.code, 0);
        assert.match(result.output, /Stock panel-launchers.*is not enabled/);
        assert.match(result.output, /no panel launchers after restart/);
    });

    it('does not warn if stock panel-launchers is present', () => {
        fs.writeFileSync(sb.dconfStore,
            `['panel1:center:0:${STOCK_UUID}:2', 'panel1:center:1:${UUID}:18']`);

        const appletDir = path.join(sb.appletParent, UUID);
        fs.symlinkSync(PROJECT_DIR, appletDir);

        const result = runScript('uninstall.sh', sb.env);
        assert.equal(result.code, 0);
        assert.ok(!result.output.includes('no panel launchers'),
            'Should not warn when stock applet remains');
    });

    it('handles missing dconf gracefully', () => {
        const cleanBin = path.join(sb.sandbox, 'clean-bin');
        fs.mkdirSync(cleanBin);
        for (const cmd of ['bash', 'python3', 'grep', 'rm', 'cat', 'echo', 'readlink']) {
            try {
                const real = execSync(`which ${cmd} 2>/dev/null`, { encoding: 'utf-8' }).trim();
                if (real) fs.symlinkSync(real, path.join(cleanBin, cmd));
            } catch (e) { /* builtin, skip */ }
        }
        const appletDir = path.join(sb.appletParent, UUID);
        fs.symlinkSync(PROJECT_DIR, appletDir);

        const env = { ...sb.env, PATH: cleanBin };
        const result = runScript('uninstall.sh', env);
        assert.equal(result.code, 0);
        assert.match(result.output, /dconf not found/);
        assert.ok(!fs.existsSync(appletDir), 'Symlink should still be removed');
    });
});

describe('install + uninstall round-trip', { concurrency: 1 }, () => {
    let sb;

    beforeEach(() => {
        sb = createSandbox();
    });

    afterEach(() => {
        sb.cleanup();
    });

    it('install then uninstall leaves a clean state', () => {
        const appletDir = path.join(sb.appletParent, UUID);

        const installResult = runInstall(sb.env);
        assert.equal(installResult.code, 0);
        assert.ok(fs.existsSync(appletDir), 'Should exist after install');

        const uninstallResult = runScript('uninstall.sh', sb.env);
        assert.equal(uninstallResult.code, 0);
        assert.ok(!fs.existsSync(appletDir), 'Should be gone after uninstall');
    });

    it('double uninstall is safe', () => {
        runInstall(sb.env);
        runScript('uninstall.sh', sb.env);

        const result = runScript('uninstall.sh', sb.env);
        assert.equal(result.code, 0);
        assert.match(result.output, /already/i);
    });
});
