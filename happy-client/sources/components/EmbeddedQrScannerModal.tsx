import * as React from 'react';
import {
    Modal,
    Pressable,
    StyleSheet,
    Text,
    View,
} from 'react-native';
import { CameraView } from 'expo-camera';

interface EmbeddedQrScannerModalProps {
    visible: boolean;
    title: string;
    subtitle: string;
    onClose: () => void;
    onScanned: (payload: string) => void;
    onMountError?: (message: string) => void;
}

export function EmbeddedQrScannerModal({
    visible,
    title,
    subtitle,
    onClose,
    onScanned,
    onMountError,
}: EmbeddedQrScannerModalProps) {
    const lockedRef = React.useRef(false);

    React.useEffect(() => {
        if (!visible) {
            lockedRef.current = false;
        }
    }, [visible]);

    const handleScanned = React.useCallback(({ data }: { data: string }) => {
        if (lockedRef.current) {
            return;
        }

        const payload = typeof data === 'string' ? data.trim() : String(data ?? '').trim();
        if (!payload) {
            return;
        }

        lockedRef.current = true;
        onClose();
        onScanned(payload);
    }, [onClose, onScanned]);

    const handleMountError = React.useCallback(({ message }: { message: string }) => {
        onClose();
        onMountError?.(message);
    }, [onClose, onMountError]);

    return (
        <Modal
            animationType="slide"
            onRequestClose={onClose}
            presentationStyle="fullScreen"
            visible={visible}
        >
            <View style={styles.screen}>
                <View style={styles.header}>
                    <View style={styles.headerCopy}>
                        <Text style={styles.title}>{title}</Text>
                        <Text style={styles.subtitle}>{subtitle}</Text>
                    </View>
                    <Pressable onPress={onClose} style={({ pressed }) => [styles.closeButton, pressed ? styles.closeButtonPressed : null]}>
                        <Text style={styles.closeText}>Close</Text>
                    </Pressable>
                </View>

                <View style={styles.previewShell}>
                    <CameraView
                        barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
                        facing="back"
                        onBarcodeScanned={handleScanned}
                        onMountError={handleMountError}
                        style={styles.preview}
                    />
                    <View pointerEvents="none" style={styles.guide}>
                        <View style={styles.guideFrame} />
                    </View>
                </View>

                <Text style={styles.hint}>
                    Move the phone closer or enlarge the desktop QR code until it locks.
                </Text>
            </View>
        </Modal>
    );
}

const styles = StyleSheet.create({
    screen: {
        flex: 1,
        backgroundColor: '#121212',
        paddingTop: 56,
        paddingHorizontal: 20,
        paddingBottom: 28,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        justifyContent: 'space-between',
        gap: 16,
        marginBottom: 20,
    },
    headerCopy: {
        flex: 1,
        gap: 6,
    },
    title: {
        color: '#fff7ee',
        fontSize: 24,
        fontWeight: '700',
    },
    subtitle: {
        color: '#d5c8b8',
        fontSize: 14,
        lineHeight: 20,
    },
    closeButton: {
        borderRadius: 999,
        backgroundColor: '#2a2a2a',
        paddingHorizontal: 14,
        paddingVertical: 9,
    },
    closeButtonPressed: {
        opacity: 0.8,
    },
    closeText: {
        color: '#fff7ee',
        fontSize: 14,
        fontWeight: '600',
    },
    previewShell: {
        flex: 1,
        overflow: 'hidden',
        borderRadius: 28,
        backgroundColor: '#000',
        borderWidth: 1,
        borderColor: '#2f2f2f',
    },
    preview: {
        flex: 1,
    },
    guide: {
        ...StyleSheet.absoluteFillObject,
        alignItems: 'center',
        justifyContent: 'center',
    },
    guideFrame: {
        width: 240,
        height: 240,
        borderRadius: 28,
        borderWidth: 3,
        borderColor: '#fff7ee',
        backgroundColor: 'transparent',
    },
    hint: {
        marginTop: 18,
        color: '#d5c8b8',
        fontSize: 14,
        lineHeight: 20,
        textAlign: 'center',
    },
});
