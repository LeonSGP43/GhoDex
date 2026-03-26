import { loadStoredSession } from './storage';

export async function bootstrapGhoDexAppShell(): Promise<void> {
    // Warm the persisted device session without reviving the legacy auth/sync stack.
    await loadStoredSession();
}
