import React from 'react';
import { Ionicons } from '@expo/vector-icons';
import { Item } from '@/components/Item';
import { ItemGroup } from '@/components/ItemGroup';
import { ItemList } from '@/components/ItemList';
import { useSettingMutable } from '@/sync/storage';
import { useUnistyles } from 'react-native-unistyles';
import { t, getLanguageNativeName, SUPPORTED_LANGUAGES, SUPPORTED_LANGUAGE_CODES, type SupportedLanguage } from '@/text';
import * as Localization from 'expo-localization';

type LanguageOption = 'auto' | SupportedLanguage;

interface LanguageItem {
    key: LanguageOption;
    title: string;
    subtitle?: string;
}

function getDetectedLanguageCode(): SupportedLanguage {
    const deviceLocale = Localization.getLocales()?.[0]?.languageTag ?? 'en-US';
    const deviceLanguage = deviceLocale.split('-')[0].toLowerCase();
    if (deviceLanguage === 'zh') {
        return 'zh-Hans';
    }
    return deviceLanguage in SUPPORTED_LANGUAGES ? deviceLanguage as SupportedLanguage : 'en';
}

export default function LanguageSettingsScreen() {
    const { theme } = useUnistyles();
    const [preferredLanguage, setPreferredLanguage] = useSettingMutable('preferredLanguage');
    const iconColor = theme.colors.textSecondary;
    const selectedColor = theme.colors.button.primary.background;

    // Get device locale for automatic detection
    const detectedLanguageName = getLanguageNativeName(getDetectedLanguageCode());

    // Current selection
    const currentSelection: LanguageOption = preferredLanguage === null ? 'auto' : 
                                           SUPPORTED_LANGUAGE_CODES.includes(preferredLanguage as SupportedLanguage) ? 
                                           preferredLanguage as SupportedLanguage : 'auto';

    // Language options - dynamically generated from supported languages
    const languageOptions: LanguageItem[] = [
        {
            key: 'auto',
            title: t('settingsLanguage.automatic'),
            subtitle: `${t('settingsLanguage.automaticSubtitle')} (${detectedLanguageName})`
        },
        ...SUPPORTED_LANGUAGE_CODES.map(code => ({
            key: code,
            title: getLanguageNativeName(code)
        }))
    ];

    const handleLanguageChange = (newLanguage: LanguageOption) => {
        if (newLanguage === currentSelection) {
            return;
        }

        const newPreference = newLanguage === 'auto' ? null : newLanguage;
        setPreferredLanguage(newPreference);
    };

    return (
        <ItemList style={{ paddingTop: 0 }}>
            <ItemGroup 
                title={t('settingsLanguage.currentLanguage')} 
                footer={t('settingsLanguage.description')}
            >
                {languageOptions.map((option) => (
                    <Item
                        key={option.key}
                        title={option.title}
                        subtitle={option.subtitle}
                        icon={<Ionicons 
                            name="language-outline" 
                            size={29} 
                            color={iconColor}
                        />}
                        rightElement={
                            currentSelection === option.key ? (
                                <Ionicons 
                                    name="checkmark" 
                                    size={20} 
                                    color={selectedColor}
                                />
                            ) : null
                        }
                        onPress={() => handleLanguageChange(option.key)}
                        showChevron={false}
                    />
                ))}
            </ItemGroup>
        </ItemList>
    );
}
