import 'react-native-gesture-handler';
import * as React from 'react';
import * as SplashScreen from 'expo-splash-screen';
import { Stack } from 'expo-router';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { KeyboardProvider } from 'react-native-keyboard-controller';
import { SafeAreaProvider, initialWindowMetrics } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { useUnistyles } from 'react-native-unistyles';
import { AuthProvider } from '@/auth/AuthContext';
import { TokenStorage, type AuthCredentials } from '@/auth/tokenStorage';
import { syncRestore } from '@/sync/sync';
import { useSetting } from '@/sync/storage';

export { ErrorBoundary } from 'expo-router';

void SplashScreen.preventAutoHideAsync().catch(() => {
    // Ignore repeated splash calls during fast refresh.
});

const AUTH_BOOTSTRAP_TIMEOUT_MS = 1500;

async function loadInitialCredentialsWithTimeout(): Promise<AuthCredentials | null> {
    return Promise.race([
        TokenStorage.getCredentials(),
        new Promise<AuthCredentials | null>((resolve) => {
            setTimeout(() => resolve(null), AUTH_BOOTSTRAP_TIMEOUT_MS);
        }),
    ]);
}

export default function RootLayout() {
    const { theme } = useUnistyles();
    const preferredLanguage = useSetting('preferredLanguage');
    const splashHiddenRef = React.useRef(false);
    const [initialCredentials, setInitialCredentials] = React.useState<AuthCredentials | null>(null);
    const languageTreeKey = preferredLanguage ?? '__auto__';

    const hideSplashScreen = React.useCallback(() => {
        if (splashHiddenRef.current) {
            return;
        }
        splashHiddenRef.current = true;
        void SplashScreen.hideAsync().catch(() => {
            // Ignore splash hide races during development.
            splashHiddenRef.current = false;
        });
    }, []);

    React.useEffect(() => {
        const frame = requestAnimationFrame(() => {
            hideSplashScreen();
        });

        return () => {
            cancelAnimationFrame(frame);
        };
    }, [hideSplashScreen]);

    const onLayoutRootView = React.useCallback(() => {
        hideSplashScreen();
    }, [hideSplashScreen]);

    React.useEffect(() => {
        let active = true;

        void (async () => {
            const credentials = await loadInitialCredentialsWithTimeout();
            if (!active) {
                return;
            }

            setInitialCredentials(credentials);

            if (!credentials) {
                return;
            }

            try {
                await syncRestore(credentials);
            } catch (error) {
                console.error('Failed to restore auth sync state:', error);
            }
        })();

        return () => {
            active = false;
        };
    }, []);

    return (
        <SafeAreaProvider initialMetrics={initialWindowMetrics}>
            <GestureHandlerRootView
                style={{ flex: 1, backgroundColor: theme.colors.groupped.background }}
                onLayout={onLayoutRootView}
            >
                <AuthProvider initialCredentials={initialCredentials}>
                    <KeyboardProvider
                        navigationBarTranslucent={true}
                        preserveEdgeToEdge={true}
                        statusBarTranslucent={true}
                    >
                        <StatusBar style={theme.dark ? 'light' : 'dark'} />
                        <Stack
                            key={languageTreeKey}
                            screenOptions={{
                                headerShown: false,
                                contentStyle: {
                                    backgroundColor: theme.colors.groupped.background,
                                },
                            }}
                        >
                            <Stack.Screen name="(app)" options={{ headerShown: false }} />
                        </Stack>
                    </KeyboardProvider>
                </AuthProvider>
            </GestureHandlerRootView>
        </SafeAreaProvider>
    );
}
