import React, { useCallback, useMemo } from 'react';
import { Platform } from 'react-native';
import { useRouter } from 'expo-router';
import { Modal } from '@/modal';
import { CommandPalette } from './CommandPalette';
import { Command } from './types';
import { useGlobalKeyboard } from '@/hooks/useGlobalKeyboard';
import { storage } from '@/sync/storage';
import { useShallow } from 'zustand/react/shallow';

export function CommandPaletteProvider({ children }: { children: React.ReactNode }) {
    const router = useRouter();
    const commandPaletteEnabled = storage(useShallow((state) => state.localSettings.commandPaletteEnabled));

    // Define available commands
    const commands = useMemo((): Command[] => {
        const cmds: Command[] = [
            {
                id: 'workspace',
                title: 'Workspace',
                subtitle: 'Open the paired desktop workspace',
                icon: 'desktop-outline',
                category: 'Navigation',
                shortcut: '⌘1',
                action: () => {
                    router.push('/');
                }
            },
            {
                id: 'connect',
                title: 'Connect Device',
                subtitle: 'Pair or replace the current desktop device',
                icon: 'link-outline',
                category: 'Navigation',
                shortcut: '⌘2',
                action: () => {
                    router.push('/gateway');
                }
            },
            {
                id: 'settings',
                title: 'Settings',
                subtitle: 'Change theme and app language',
                icon: 'settings-outline',
                category: 'Navigation',
                shortcut: '⌘3',
                action: () => {
                    router.push('/settings');
                }
            },
        ];

        // Dev commands (if in development)
        if (__DEV__) {
            cmds.push({
                id: 'dev-menu',
                title: 'Developer Menu',
                subtitle: 'Access developer tools',
                icon: 'code-slash-outline',
                category: 'Developer',
                action: () => {
                    router.push('/dev');
                }
            });
        }

        return cmds;
    }, [router]);

    const showCommandPalette = useCallback(() => {
        if (Platform.OS !== 'web' || !commandPaletteEnabled) return;
        
        Modal.show({
            component: CommandPalette,
            props: {
                commands,
            }
        } as any);
    }, [commands, commandPaletteEnabled]);

    // Set up global keyboard handler only if feature is enabled
    useGlobalKeyboard(commandPaletteEnabled ? showCommandPalette : () => {});

    return <>{children}</>;
}
