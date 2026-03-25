import { Stack } from 'expo-router';
import * as React from 'react';

export const unstable_settings = {
    initialRouteName: 'index',
};

export default function AppLayout() {
    return (
        <Stack
            screenOptions={{
                headerShadowVisible: false,
                headerStyle: {
                    backgroundColor: '#f4efe6',
                },
                headerTintColor: '#16120f',
                headerTitleStyle: {
                    fontSize: 18,
                    fontWeight: '700',
                },
                contentStyle: {
                    backgroundColor: '#f4efe6',
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
                    headerTitle: 'Pair Device',
                }}
            />
            <Stack.Screen
                name="gateway"
                options={{
                    headerTitle: 'Settings',
                }}
            />
        </Stack>
    );
}
