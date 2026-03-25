import { useCameraPermissions } from "expo-camera";
import { Platform } from "react-native";

interface ScannerPermissionOptions {
    requireCameraOnAndroid?: boolean;
}

export function useCheckScannerPermissions(): (options?: ScannerPermissionOptions) => Promise<boolean> {
    const [cameraPermission, requestCameraPermission] = useCameraPermissions();

    return async (options) => {
        const requireCameraOnAndroid = options?.requireCameraOnAndroid ?? false;
        if (Platform.OS === 'android' && !requireCameraOnAndroid) {
            // Android's Google code scanner path does not require direct camera access.
            return true;
        }

        if (!cameraPermission) {
            const reqRes = await requestCameraPermission();
            return reqRes.granted;
        }

        if (!cameraPermission.granted) {
            const reqRes = await requestCameraPermission();
            return reqRes.granted;
        }

        return true;
    }
}
