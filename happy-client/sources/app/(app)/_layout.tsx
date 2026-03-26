import { Redirect, Stack, useSegments } from 'expo-router';
import * as React from 'react';
import { useUnistyles } from 'react-native-unistyles';
import { isAllowedGhoDexProductRoute, normalizeAppRouteFromSegments } from '@/ghodex/routes';

export const unstable_settings = {
    initialRouteName: 'index',
};

export default function AppLayout() {
    const { theme } = useUnistyles();
    const segments = useSegments();
    const route = React.useMemo(() => normalizeAppRouteFromSegments(segments), [segments]);

    if (!isAllowedGhoDexProductRoute(route, { development: __DEV__ })) {
        return <Redirect href="/" />;
    }

    return (
        <Stack
            screenOptions={{
                headerShadowVisible: false,
                headerStyle: {
                    backgroundColor: theme.colors.header.background,
                },
                headerTintColor: theme.colors.header.tint,
                headerTitleStyle: {
                    fontSize: 18,
                    fontWeight: '700',
                },
                contentStyle: {
                    backgroundColor: theme.colors.groupped.background,
                },
            }}
        >
            <Stack.Screen
                name="index"
                options={{
                    headerShown: false,
                }}
            />
            <Stack.Screen
                name="pairing"
                options={{
                    headerTitle: 'Device',
                }}
            />
            <Stack.Screen
                name="gateway"
                options={{
                    headerTitle: 'Device',
                }}
            />
            <Stack.Screen
                name="settings"
                options={{
                    headerShown: false,
                }}
            />
        </Stack>
    );
}
