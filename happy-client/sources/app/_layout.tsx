import 'react-native-gesture-handler';
import * as React from 'react';
import * as SplashScreen from 'expo-splash-screen';
import { Stack } from 'expo-router';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { KeyboardProvider } from 'react-native-keyboard-controller';
import { SafeAreaProvider, initialWindowMetrics } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';
import { useUnistyles } from 'react-native-unistyles';
import { bootstrapGhoDexAppShell } from '@/ghodex/appShell';
import {
    recordBootstrapCompleted,
    recordBootstrapFailed,
    recordBootstrapStarted,
    recordLaunchReady,
    recordLaunchStarted,
} from '@/ghodex/observability';
import { useSetting } from '@/sync/storage';

export { ErrorBoundary } from 'expo-router';

void SplashScreen.preventAutoHideAsync().catch(() => {
    // Ignore repeated splash calls during fast refresh.
});
recordLaunchStarted();

export default function RootLayout() {
    const { theme } = useUnistyles();
    const preferredLanguage = useSetting('preferredLanguage');
    const splashHiddenRef = React.useRef(false);
    const launchReadyRecordedRef = React.useRef(false);
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
        if (!launchReadyRecordedRef.current) {
            launchReadyRecordedRef.current = true;
            recordLaunchReady();
        }
        hideSplashScreen();
    }, [hideSplashScreen]);

    React.useEffect(() => {
        recordBootstrapStarted();
        void (async () => {
            try {
                await bootstrapGhoDexAppShell();
                recordBootstrapCompleted();
            } catch (error) {
                recordBootstrapFailed();
                console.warn('Failed to hydrate the GhoDex device session during bootstrap:', error);
            }
        })();
    }, []);

    return (
        <SafeAreaProvider initialMetrics={initialWindowMetrics}>
            <GestureHandlerRootView
                style={{ flex: 1, backgroundColor: theme.colors.groupped.background }}
                onLayout={onLayoutRootView}
            >
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
            </GestureHandlerRootView>
        </SafeAreaProvider>
    );
}
