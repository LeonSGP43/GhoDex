const fs = require('node:fs');
const path = require('node:path');

const appConfigDir = __dirname;
const variant = process.env.APP_ENV || 'development';
const name = {
    development: "GhoDex Remote (dev)",
    preview: "GhoDex Remote (preview)",
    production: "GhoDex Remote"
}[variant];
const bundleId = {
    development: "com.leongong.ghodex.remote.dev",
    preview: "com.leongong.ghodex.remote.preview",
    production: "com.leongong.ghodex.remote"
}[variant];
const repoVersion = fs.readFileSync(path.join(appConfigDir, '..', 'VERSION'), 'utf8').trim();
const [major, minor, patch] = repoVersion.split('.').map((value) => Number.parseInt(value, 10));
const androidVersionCode = (major * 10000) + (minor * 100) + patch;

module.exports = {
    expo: {
        name,
        slug: "ghodex-remote",
        version: repoVersion,
        runtimeVersion: "1",
        orientation: "default",
        icon: "./sources/assets/images/icon.png",
        scheme: "ghodex-remote",
        userInterfaceStyle: "automatic",
        newArchEnabled: true,
        notification: {
            icon: "./sources/assets/images/icon-notification.png",
            iosDisplayInForeground: true
        },
        ios: {
            supportsTablet: true,
            bundleIdentifier: bundleId,
            config: {
                usesNonExemptEncryption: false
            },
            infoPlist: {
                NSMicrophoneUsageDescription: "Allow $(PRODUCT_NAME) to access your microphone for future voice controls.",
                NSLocalNetworkUsageDescription: "Allow $(PRODUCT_NAME) to find and connect to local devices on your network.",
                NSBonjourServices: ["_http._tcp", "_https._tcp"]
            }
        },
        android: {
            versionCode: androidVersionCode,
            adaptiveIcon: {
                foregroundImage: "./sources/assets/images/icon-adaptive.png",
                monochromeImage: "./sources/assets/images/icon-monochrome.png",
                backgroundColor: "#18171C"
            },
            permissions: [
                "android.permission.RECORD_AUDIO",
                "android.permission.MODIFY_AUDIO_SETTINGS",
                "android.permission.ACCESS_NETWORK_STATE",
                "android.permission.POST_NOTIFICATIONS",
            ],
            blockedPermissions: [
                "android.permission.ACTIVITY_RECOGNITION"
            ],
            edgeToEdgeEnabled: true,
            package: bundleId,
            intentFilters: []
        },
        web: {
            bundler: "metro",
            output: "single",
            favicon: "./sources/assets/images/favicon.png"
        },
        plugins: [
            require("./plugins/withEinkCompatibility.js"),
            [
                "expo-router",
                {
                    root: "./sources/app"
                }
            ],
            "expo-updates",
            "expo-asset",
            "expo-localization",
            "expo-mail-composer",
            "expo-secure-store",
            "expo-web-browser",
            "react-native-vision-camera",
            "@more-tech/react-native-libsodium",
            "react-native-audio-api",
            "@livekit/react-native-expo-plugin",
            "@config-plugins/react-native-webrtc",
            [
                "expo-audio",
                {
                    microphonePermission: "Allow $(PRODUCT_NAME) to access your microphone for voice conversations."
                }
            ],
            [
                "expo-location",
                {
                    locationAlwaysAndWhenInUsePermission: "Allow $(PRODUCT_NAME) to discover nearby desktop peers.",
                    locationAlwaysPermission: "Allow $(PRODUCT_NAME) to discover nearby desktop peers.",
                    locationWhenInUsePermission: "Allow $(PRODUCT_NAME) to discover nearby desktop peers."
                }
            ],
            [
                "expo-calendar",
                {
                    "calendarPermission": "Allow $(PRODUCT_NAME) to access calendar data."
                }
            ],
            [
                "expo-camera",
                {
                    cameraPermission: "Allow $(PRODUCT_NAME) to access your camera to scan pairing QR codes.",
                    microphonePermission: "Allow $(PRODUCT_NAME) to access your microphone for future voice controls.",
                    recordAudioAndroid: true
                }
            ],
            [
                "expo-notifications",
                {
                    "enableBackgroundRemoteNotifications": true
                }
            ],
            [
                'expo-splash-screen',
                {
                    ios: {
                        backgroundColor: "#F2F2F7",
                        dark: {
                            backgroundColor: "#1C1C1E",
                        }
                    },
                    android: {
                        image: "./sources/assets/images/splash-android-light.png",
                        backgroundColor: "#F5F5F5",
                        dark: {
                            image: "./sources/assets/images/splash-android-dark.png",
                            backgroundColor: "#1e1e1e",
                        }
                    }
                }
            ]
        ],
        experiments: {
            typedRoutes: true
        },
        extra: {
            router: {
                root: "./sources/app"
            },
            app: {
                controlHarnessHost: process.env.EXPO_PUBLIC_GHODEX_GATEWAY_HOST,
                controlHarnessPort: process.env.EXPO_PUBLIC_GHODEX_GATEWAY_PORT
            }
        }
    }
};
