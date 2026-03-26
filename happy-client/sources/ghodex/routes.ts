const PRODUCT_ROUTE_ALLOWLIST = new Set([
    'index',
    'gateway',
    'pairing',
    'settings',
    'settings/language',
]);

function stripRouteGroups(segments: readonly string[]): string[] {
    return segments.filter((segment) => segment.length > 0 && !segment.startsWith('('));
}

export function normalizeAppRouteFromSegments(segments: readonly string[]): string {
    const normalizedRoute = stripRouteGroups(segments).join('/');
    return normalizedRoute.length > 0 ? normalizedRoute : 'index';
}

export function isAllowedGhoDexProductRoute(
    route: string,
    options?: {
        development?: boolean;
    },
): boolean {
    if (PRODUCT_ROUTE_ALLOWLIST.has(route)) {
        return true;
    }

    if (options?.development) {
        return route === 'dev' || route.startsWith('dev/');
    }

    return false;
}
