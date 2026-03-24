import 'react-native-gesture-handler';
import * as React from 'react';
import * as SplashScreen from 'expo-splash-screen';
import { Stack } from 'expo-router';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { SafeAreaProvider, initialWindowMetrics } from 'react-native-safe-area-context';
import { StatusBar } from 'expo-status-bar';

export { ErrorBoundary } from 'expo-router';

void SplashScreen.preventAutoHideAsync().catch(() => {
    // Ignore repeated splash calls during fast refresh.
});

export default function RootLayout() {
    const [ready, setReady] = React.useState(false);

    React.useEffect(() => {
        setReady(true);
    }, []);

    const onLayoutRootView = React.useCallback(() => {
        if (!ready) {
            return;
        }
        void SplashScreen.hideAsync().catch(() => {
            // Ignore splash hide races during development.
        });
    }, [ready]);

    if (!ready) {
        return null;
    }

    return (
        <SafeAreaProvider initialMetrics={initialWindowMetrics}>
            <GestureHandlerRootView style={{ flex: 1 }} onLayout={onLayoutRootView}>
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
            </GestureHandlerRootView>
        </SafeAreaProvider>
    );
}
