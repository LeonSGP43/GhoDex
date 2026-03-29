import * as React from 'react';
import * as Localization from 'expo-localization';
import Constants from 'expo-constants';
import * as Application from 'expo-application';
import { Stack, useRouter } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { useLocalSettingMutable, useSettingMutable } from '@/sync/storage';
import { useUnistyles } from 'react-native-unistyles';
import { applyThemePreference, resolveThemePreference } from '@/unistyles';
import { SUPPORTED_LANGUAGES, getLanguageNativeName, t, type SupportedLanguage } from '@/text';

function getDetectedLanguageCode(): SupportedLanguage {
    const deviceLocale = Localization.getLocales()?.[0]?.languageTag ?? 'en-US';
    const deviceLanguage = deviceLocale.split('-')[0].toLowerCase();
    if (deviceLanguage === 'zh') {
        return 'zh-Hans';
    }
    return deviceLanguage in SUPPORTED_LANGUAGES ? deviceLanguage as SupportedLanguage : 'en';
}

function getLanguageDisplayText(preferredLanguage: string | null) {
    if (preferredLanguage === null) {
        const detectedLanguageName = getLanguageNativeName(getDetectedLanguageCode());
        return `${t('settingsLanguage.automatic')} (${detectedLanguageName})`;
    }

    if (preferredLanguage in SUPPORTED_LANGUAGES) {
        return getLanguageNativeName(preferredLanguage as keyof typeof SUPPORTED_LANGUAGES);
    }

    return t('settingsLanguage.automatic');
}

function terminalInputModeCopy(preferredLanguage: string | null, mode: 'simple' | 'realtime') {
    const isZh = preferredLanguage === 'zh-Hans' || (preferredLanguage === null && getDetectedLanguageCode() === 'zh-Hans');

    if (isZh) {
        return {
            title: '终端输入模式',
            subtitle: mode === 'simple'
                ? '简单命令：点击发送后立即执行命令。'
                : '实时按键流：输入即发送，接近 SSH 交互。',
            detail: mode === 'simple' ? '简单命令' : '实时按键流',
        };
    }

    return {
        title: 'Terminal Input Mode',
        subtitle: mode === 'simple'
            ? 'Simple command mode executes immediately on Send.'
            : 'Realtime key stream sends keys immediately like SSH.',
        detail: mode === 'simple' ? 'Simple Command' : 'Realtime Key Stream',
    };
}

export default function GhoDexSettingsScreen() {
    const router = useRouter();
    const { theme } = useUnistyles();
    const appVersion = Application.nativeApplicationVersion ?? Constants.expoConfig?.version ?? '1.0.0';
    const [themePreference, setThemePreference] = useLocalSettingMutable('themePreference');
    const [mobileTerminalInputMode, setMobileTerminalInputMode] = useLocalSettingMutable('mobileTerminalInputMode');
    const [preferredLanguage] = useSettingMutable('preferredLanguage');
    const resolvedThemePreference = resolveThemePreference(themePreference, theme.dark);
    const iconColor = theme.colors.textSecondary;

    const handleToggleTheme = React.useCallback(() => {
        const nextTheme = resolvedThemePreference === 'dark' ? 'light' : 'dark';
        setThemePreference(nextTheme);
        applyThemePreference(nextTheme);
    }, [resolvedThemePreference, setThemePreference]);

    const languageDetail = React.useMemo(
        () => getLanguageDisplayText(preferredLanguage),
        [preferredLanguage]
    );
    const inputModeCopy = React.useMemo(
        () => terminalInputModeCopy(preferredLanguage, mobileTerminalInputMode),
        [mobileTerminalInputMode, preferredLanguage],
    );
    const handleToggleTerminalInputMode = React.useCallback(() => {
        setMobileTerminalInputMode(mobileTerminalInputMode === 'simple' ? 'realtime' : 'simple');
    }, [mobileTerminalInputMode, setMobileTerminalInputMode]);

    return (
        <>
            <Stack.Screen
                options={{
                    title: t('settings.title'),
                }}
            />
            <ItemList style={{ paddingTop: 0 }}>
                <ItemGroup
                    title={t('settings.title')}
                    footer={t('settings.appearanceSubtitle')}
                >
                    <Item
                        title={t('settingsAppearance.theme')}
                        subtitle={resolvedThemePreference === 'dark'
                            ? t('settingsAppearance.themeDescriptions.dark')
                            : t('settingsAppearance.themeDescriptions.light')}
                        detail={resolvedThemePreference === 'dark'
                            ? t('settingsAppearance.themeOptions.dark')
                            : t('settingsAppearance.themeOptions.light')}
                        icon={<Ionicons name="contrast-outline" size={29} color={iconColor} />}
                        onPress={handleToggleTheme}
                        showChevron={false}
                    />
                    <Item
                        title={t('settingsLanguage.title')}
                        subtitle={t('settingsLanguage.description')}
                        detail={languageDetail}
                        icon={<Ionicons name="language-outline" size={29} color={iconColor} />}
                        onPress={() => router.push('/settings/language')}
                    />
                    <Item
                        title={inputModeCopy.title}
                        subtitle={inputModeCopy.subtitle}
                        detail={inputModeCopy.detail}
                        icon={<Ionicons name="terminal-outline" size={29} color={iconColor} />}
                        onPress={handleToggleTerminalInputMode}
                        showChevron={false}
                    />
                </ItemGroup>

                <ItemGroup title={t('settings.about')}>
                    <Item
                        title={t('common.version')}
                        detail={appVersion}
                        icon={<Ionicons name="information-circle-outline" size={29} color={iconColor} />}
                        showChevron={false}
                    />
                </ItemGroup>
            </ItemList>
        </>
    );
}
