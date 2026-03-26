import { describe, expect, it, vi } from 'vitest';

const { loadStoredSession } = vi.hoisted(() => ({
    loadStoredSession: vi.fn(async () => undefined),
}));

vi.mock('./storage', () => ({
    loadStoredSession,
}));

import { bootstrapGhoDexAppShell } from './appShell';

describe('bootstrapGhoDexAppShell', () => {
    it('only warms the stored GhoDex device session', async () => {
        await bootstrapGhoDexAppShell();

        expect(loadStoredSession).toHaveBeenCalledTimes(1);
    });
});
