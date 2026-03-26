import * as z from 'zod';

const RESERVED_GHODEX_CONNECTION_SETTING_KEYS = new Set([
    'host',
    'port',
    'pairingCode',
    'authToken',
    'tokenId',
    'scopes',
    'requestedScopes',
    'liveUpdatesEnabled',
    'pollIntervalMs',
    'transportMode',
    'preferredDesktopId',
    'desktopId',
    'desktopIdentity',
    'deviceId',
    'deviceIdentity',
    'pairingState',
]);

function stripReservedGhoDexConnectionFields<T extends Record<string, unknown>>(value: T): T {
    const nextValue = { ...value };
    for (const key of RESERVED_GHODEX_CONNECTION_SETTING_KEYS) {
        delete nextValue[key];
    }
    return nextValue;
}

//
// Settings Schema
//

// Current schema version for backward compatibility
export const SUPPORTED_SCHEMA_VERSION = 2;

export const SettingsSchema = z.object({
    // Schema version for compatibility detection
    schemaVersion: z.number().default(SUPPORTED_SCHEMA_VERSION).describe('Settings schema version for compatibility checks'),

    viewInline: z.boolean().describe('Whether to view inline tool calls'),
    inferenceOpenAIKey: z.string().nullish().describe('OpenAI API key for inference'),
    expandTodos: z.boolean().describe('Whether to expand todo lists'),
    showLineNumbers: z.boolean().describe('Whether to show line numbers in diffs'),
    showLineNumbersInToolViews: z.boolean().describe('Whether to show line numbers in tool view diffs'),
    wrapLinesInDiffs: z.boolean().describe('Whether to wrap long lines in diff views'),
    analyticsOptOut: z.boolean().describe('Whether to opt out of anonymous analytics'),
    experiments: z.boolean().describe('Whether to enable experimental features'),
    alwaysShowContextSize: z.boolean().describe('Always show context size in agent input'),
    agentInputEnterToSend: z.boolean().describe('Whether pressing Enter submits/sends in the agent input (web)'),
    avatarStyle: z.string().describe('Avatar display style'),
    showFlavorIcons: z.boolean().describe('Whether to show AI provider icons in avatars'),
    compactSessionView: z.boolean().describe('Whether to use compact view for active sessions'),
    hideInactiveSessions: z.boolean().describe('Hide inactive sessions in the main list'),
    expResumeSession: z.boolean().describe('Enable experimental session resume feature'),
    reviewPromptAnswered: z.boolean().describe('Whether the review prompt has been answered'),
    reviewPromptLikedApp: z.boolean().nullish().describe('Whether user liked the app when asked'),
    voiceAssistantLanguage: z.string().nullable().describe('Preferred language for voice assistant (null for auto-detect)'),
    preferredLanguage: z.string().nullable().describe('Preferred UI language (null for auto-detect from device locale)'),
    recentMachinePaths: z.array(z.object({
        machineId: z.string(),
        path: z.string()
    })).describe('Last 10 machine-path combinations, ordered by most recent first'),
    lastUsedAgent: z.string().nullable().describe('Last selected agent type for new sessions'),
    lastUsedPermissionMode: z.string().nullable().describe('Last selected permission mode for new sessions'),
    lastUsedModelMode: z.string().nullable().describe('Last selected model mode for new sessions'),
    // Dismissed CLI warning banners (supports both per-machine and global dismissal)
    dismissedCLIWarnings: z.object({
        perMachine: z.record(z.string(), z.object({
            claude: z.boolean().optional(),
            codex: z.boolean().optional(),
            gemini: z.boolean().optional(),
            openclaw: z.boolean().optional(),
        })).default({}),
        global: z.object({
            claude: z.boolean().optional(),
            codex: z.boolean().optional(),
            gemini: z.boolean().optional(),
            openclaw: z.boolean().optional(),
        }).default({}),
    }).default({ perMachine: {}, global: {} }).describe('Tracks which CLI installation warnings user has dismissed (per-machine or globally)'),
});

//
// NOTE: Settings must be a flat object with no to minimal nesting, one field == one setting,
// you can name them with a prefix if you want to group them, but don't nest them.
// You can nest if value is a single value (like image with url and width and height)
// Settings are always merged with defaults and field by field.
//
// This structure must be forward and backward compatible. Meaning that some versions of the app
// could be missing some fields or have a new fields. Everything must be preserved and client must
// only touch the fields it knows about.
//

const SettingsSchemaPartial = SettingsSchema.partial();

export type Settings = z.infer<typeof SettingsSchema>;

//
// Defaults
//

export const settingsDefaults: Settings = {
    schemaVersion: SUPPORTED_SCHEMA_VERSION,
    viewInline: false,
    inferenceOpenAIKey: null,
    expandTodos: true,
    showLineNumbers: true,
    showLineNumbersInToolViews: false,
    wrapLinesInDiffs: false,
    analyticsOptOut: false,
    experiments: false,
    alwaysShowContextSize: false,
    agentInputEnterToSend: true,
    avatarStyle: 'brutalist',
    showFlavorIcons: false,
    compactSessionView: false,
    hideInactiveSessions: false,
    expResumeSession: false,
    reviewPromptAnswered: false,
    reviewPromptLikedApp: null,
    voiceAssistantLanguage: null,
    preferredLanguage: null,
    recentMachinePaths: [],
    lastUsedAgent: null,
    lastUsedPermissionMode: null,
    lastUsedModelMode: null,
    dismissedCLIWarnings: { perMachine: {}, global: {} },
};
Object.freeze(settingsDefaults);

function normalizePreferredLanguage(value: string | null | undefined): string | null | undefined {
    if (value === undefined) {
        return undefined;
    }

    if (value === null || value === 'en') {
        return value;
    }

    if (value === 'zh' || value === 'zh-Hans' || value === 'zh-Hant') {
        return 'zh-Hans';
    }

    return null;
}

//
// Resolving
//

export function settingsParse(settings: unknown): Settings {
    // Handle null/undefined/invalid inputs
    if (!settings || typeof settings !== 'object') {
        return { ...settingsDefaults };
    }

    const sanitizedSettings = stripReservedGhoDexConnectionFields(settings as Record<string, unknown>);

    const parsed = SettingsSchemaPartial.safeParse(sanitizedSettings);
    if (!parsed.success) {
        // For invalid settings, preserve unknown fields but use defaults for known fields
        const unknownFields = { ...sanitizedSettings };
        // Remove all known schema fields from unknownFields
        const knownFields = Object.keys(SettingsSchema.shape);
        knownFields.forEach(key => delete unknownFields[key]);
        return { ...settingsDefaults, ...unknownFields };
    }

    const normalizedPreferredLanguage = normalizePreferredLanguage(parsed.data.preferredLanguage);
    if (normalizedPreferredLanguage !== undefined) {
        parsed.data.preferredLanguage = normalizedPreferredLanguage;
    }

    // Merge defaults, parsed settings, and preserve unknown fields
    const unknownFields = { ...sanitizedSettings };
    // Remove known fields from unknownFields to preserve only the unknown ones
    Object.keys(parsed.data).forEach(key => delete unknownFields[key]);

    return { ...settingsDefaults, ...parsed.data, ...unknownFields };
}

//
// Applying changes
// NOTE: May be something more sophisticated here around defaults and merging, but for now this is fine.
//

export function applySettings(settings: Settings, delta: Partial<Settings>): Settings {
    // Original behavior: start with settings, apply delta, fill in missing with defaults
    const result = stripReservedGhoDexConnectionFields({ ...settings, ...delta });

    // Fill in any missing fields with defaults
    Object.keys(settingsDefaults).forEach(key => {
        if (!(key in result)) {
            (result as any)[key] = (settingsDefaults as any)[key];
        }
    });

    return result;
}
