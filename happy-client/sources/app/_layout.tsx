import 'react-native-gesture-handler';
import * as React from 'react';
import * as SplashScreen from 'expo-splash-screen';
import { Stack } from 'expo-router';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { KeyboardProvider } from 'react-native-keyboard-controller';
import { SafeAreaProvider, initialWindowMetrics } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';

export { ErrorBoundary } from 'expo-router';

void SplashScreen.preventAutoHideAsync().catch(() => {
    // Ignore repeated splash calls during fast refresh.
});

export default function RootLayout() {
    const splashHiddenRef = React.useRef(false);

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

    return (
        <SafeAreaProvider initialMetrics={initialWindowMetrics}>
            <GestureHandlerRootView style={{ flex: 1 }} onLayout={onLayoutRootView}>
                <KeyboardProvider
                    navigationBarTranslucent={true}
                    preserveEdgeToEdge={true}
                    statusBarTranslucent={true}
                >
                    <StatusBar style="dark" />
                    <Stack
                        screenOptions={{
                            headerShown: false,
                            contentStyle: {
                                backgroundColor: '#f4efe6',
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
