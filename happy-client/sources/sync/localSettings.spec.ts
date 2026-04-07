import { describe, expect, it } from "vitest";

import {
    applyLocalSettings,
    localSettingsDefaults,
    localSettingsParse,
} from "./localSettings";

describe("localSettings", () => {
    it("returns defaults for invalid payload", () => {
        expect(localSettingsParse(null)).toEqual(localSettingsDefaults);
        expect(localSettingsParse(undefined)).toEqual(localSettingsDefaults);
        expect(localSettingsParse("invalid")).toEqual(localSettingsDefaults);
    });

    it("parses terminal input and display mode", () => {
        const parsed = localSettingsParse({
            mobileTerminalInputMode: "realtime",
            mobileTerminalDisplayMode: "text",
        });

        expect(parsed.mobileTerminalInputMode).toBe("realtime");
        expect(parsed.mobileTerminalDisplayMode).toBe("text");
    });

    it("falls back to terminal display mode when value is invalid", () => {
        const parsed = localSettingsParse({
            mobileTerminalDisplayMode: "unknown",
        });

        expect(parsed.mobileTerminalDisplayMode).toBe("terminal");
    });

    it("applies delta updates for mobile terminal modes", () => {
        const next = applyLocalSettings(localSettingsDefaults, {
            mobileTerminalInputMode: "realtime",
            mobileTerminalDisplayMode: "text",
        });

        expect(next.mobileTerminalInputMode).toBe("realtime");
        expect(next.mobileTerminalDisplayMode).toBe("text");
    });
});
