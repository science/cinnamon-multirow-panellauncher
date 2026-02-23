const { describe, it } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const schema = JSON.parse(fs.readFileSync(path.join(ROOT, 'settings-schema.json'), 'utf8'));
const metadata = JSON.parse(fs.readFileSync(path.join(ROOT, 'metadata.json'), 'utf8'));

describe('metadata.json', () => {
    it('has the correct UUID', () => {
        assert.equal(metadata.uuid, 'multirow-panel-launchers@cinnamon');
    });

    it('has updated name', () => {
        assert.equal(metadata.name, 'Multi-Row Panel Launchers');
    });

    it('claims panellauncher role', () => {
        assert.equal(metadata.role, 'panellauncher');
    });

    it('allows multiple instances', () => {
        assert.equal(metadata['max-instances'], -1);
    });
});

describe('settings-schema.json', () => {
    describe('Behavior section', () => {
        it('has launcherList as generic type', () => {
            const s = schema['launcherList'];
            assert.ok(s, 'missing launcherList');
            assert.equal(s.type, 'generic');
            assert.ok(Array.isArray(s.default), 'default should be an array');
        });

        it('has allow-dragging switch', () => {
            const s = schema['allow-dragging'];
            assert.ok(s, 'missing allow-dragging');
            assert.equal(s.type, 'switch');
            assert.equal(s.default, true);
        });
    });

    describe('Multi-Row section', () => {
        it('has a multi-row section header', () => {
            assert.ok(schema['section-multirow'], 'missing section-multirow');
            assert.equal(schema['section-multirow'].type, 'section');
        });

        it('has max-rows as spinbutton with correct range', () => {
            const s = schema['max-rows'];
            assert.ok(s, 'missing max-rows');
            assert.equal(s.type, 'spinbutton');
            assert.equal(s.default, 2);
            assert.equal(s.min, 1);
            assert.equal(s.max, 4);
        });
    });

    describe('Appearance section', () => {
        it('has an appearance section header', () => {
            assert.ok(schema['section-appearance'], 'missing section-appearance');
            assert.equal(schema['section-appearance'].type, 'section');
        });

        it('has icon-size-override spinbutton (0=auto, max 64)', () => {
            const s = schema['icon-size-override'];
            assert.ok(s, 'missing icon-size-override');
            assert.equal(s.type, 'spinbutton');
            assert.equal(s.default, 0);
            assert.equal(s.min, 0);
            assert.equal(s.max, 64);
            assert.equal(s.step, 2);
        });
    });
});
