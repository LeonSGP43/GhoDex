import { describe, expect, it } from 'vitest';
import { isAllowedGhoDexProductRoute, normalizeAppRouteFromSegments } from './routes';

describe('normalizeAppRouteFromSegments', () => {
    it('collapses the workspace route to index', () => {
        expect(normalizeAppRouteFromSegments(['(app)'])).toBe('index');
    });

    it('strips route groups from nested routes', () => {
        expect(normalizeAppRouteFromSegments(['(app)', 'settings', 'language'])).toBe('settings/language');
    });
});

describe('isAllowedGhoDexProductRoute', () => {
    it('allows the GhoDex production surface', () => {
        expect(isAllowedGhoDexProductRoute('index')).toBe(true);
        expect(isAllowedGhoDexProductRoute('gateway')).toBe(true);
        expect(isAllowedGhoDexProductRoute('pairing')).toBe(true);
        expect(isAllowedGhoDexProductRoute('settings')).toBe(true);
        expect(isAllowedGhoDexProductRoute('settings/language')).toBe(true);
    });

    it('blocks legacy non-GhoDex routes in production', () => {
        expect(isAllowedGhoDexProductRoute('friends')).toBe(false);
        expect(isAllowedGhoDexProductRoute('settings/account')).toBe(false);
        expect(isAllowedGhoDexProductRoute('session/123')).toBe(false);
        expect(isAllowedGhoDexProductRoute('dev')).toBe(false);
    });

    it('keeps dev routes available in development only', () => {
        expect(isAllowedGhoDexProductRoute('dev', { development: true })).toBe(true);
        expect(isAllowedGhoDexProductRoute('dev/logs', { development: true })).toBe(true);
        expect(isAllowedGhoDexProductRoute('friends', { development: true })).toBe(false);
    });
});
