import * as React from 'react';
import {
    Alert,
    InteractionManager,
    Modal,
    Pressable,
    ScrollView,
    Text,
    TextInput,
    View,
} from 'react-native';
import { useRouter } from 'expo-router';
import { useFocusEffect } from '@react-navigation/native';
import { CameraView } from 'expo-camera';
import { StyleSheet, useUnistyles } from 'react-native-unistyles';
import { pairingBegin, pairingExchange } from '@/ghodex/gateway';
import { recordScreenReady, recordScreenStarted } from '@/ghodex/observability';
import { parseGatewayPairingQrPayload } from '@/ghodex/pairingQr';
import {
    applyPairingExchangeToSession,
    INITIAL_GATEWAY_SESSION,
    POLL_INTERVAL_OPTIONS,
    sanitizePollInterval,
    sanitizePort,
} from '@/ghodex/sessionState';
import { clearStoredSession, getCachedStoredSession, loadStoredSession, saveStoredSession, type StoredSession } from '@/ghodex/storage';
import { ActionButton, InfoPill, SectionValue, SurfaceCard } from '@/ghodex/ui';
import { useCheckScannerPermissions } from '@/hooks/useCheckCameraPermissions';
import { getCurrentLanguage } from '@/text';

type BusyAction = 'begin' | 'exchange' | 'scan' | 'save' | 'clear' | null;

function getGatewayCopy() {
    if (getCurrentLanguage() === 'zh-Hans') {
        return {
            screenTitle: '设备',
            screenSubtitle: '扫描桌面端二维码完成绑定或替换这台手机当前连接的设备。',
            paired: '已绑定',
            awaitingPairing: '等待绑定',
            realtimeStream: '实时流',
            polling: (ms: number) => `轮询 ${ms}ms`,
            scanToReplace: '扫码替换当前设备',
            scanPairingQr: '扫描绑定二维码',
            backToWorkspace: '返回工作区',
            deviceErrorTitle: '设备错误',
            savedSessionTitle: '已保存连接',
            savedSessionSubtitle: '这台手机会保留当前桌面连接，直到你清除或重新绑定。',
            tokenLabel: '令牌',
            tokenIssued: '已签发',
            tokenMissing: '未签发',
            tokenIdLabel: '令牌 ID',
            tokenIdMissing: '尚未生成',
            scopesLabel: '权限范围',
            scopesMissing: '无',
            advancedTitle: '高级连接选项',
            advancedSubtitle: '只在扫码不可用或需要调试时打开，默认不影响日常进入速度。',
            showAdvanced: '展开高级选项',
            hideAdvanced: '收起高级选项',
            gatewayTitle: '网关端点',
            gatewaySubtitle: '仅在二维码绑定不可用时，作为手动网络回退入口使用。',
            resolvedPort: '解析后的端口',
            saveConnection: '保存连接',
            syncModeTitle: '同步方式',
            syncModeSubtitle: '选择这台手机如何刷新桌面状态。',
            realtimeOption: '实时流',
            pollingOption: '仅轮询',
            currentSync: '当前同步',
            currentSyncRealtime: '当前激活终端使用订阅流',
            currentSyncPolling: '仅使用定时轮询',
            pollingInterval: '回退 / 轮询间隔',
            manualPairingTitle: '手动绑定',
            manualPairingSubtitle: '仅在二维码无法使用时作为后备方案。',
            requestedScopes: '请求权限',
            beginPairing: '开始绑定',
            exchangePairing: '交换绑定',
            resetTitle: '重置设备',
            resetSubtitle: '从这台手机上移除已保存的桌面连接。',
            clearSavedSession: '清除已保存连接',
            scannerTitle: '扫描绑定二维码',
            scannerSubtitle: '请将后置摄像头对准桌面显示的二维码。',
            close: '关闭',
            cameraPermissionRequiredTitle: '需要相机权限',
            cameraPermissionRequiredMessage: '扫描绑定二维码需要相机权限。',
            pairingQrErrorTitle: '绑定二维码错误',
            qrScannerErrorTitle: '二维码扫描错误',
            unexpectedDeviceError: '设备出现未知错误',
        };
    }

    return {
        screenTitle: 'Device',
        screenSubtitle: 'Scan a desktop QR code to pair or replace the device linked to this phone.',
        paired: 'Paired',
        awaitingPairing: 'Awaiting pairing',
        realtimeStream: 'Realtime stream',
        polling: (ms: number) => `Polling ${ms}ms`,
        scanToReplace: 'Scan To Replace Device',
        scanPairingQr: 'Scan Pairing QR',
        backToWorkspace: 'Back To Workspace',
        deviceErrorTitle: 'Device error',
        savedSessionTitle: 'Saved Session',
        savedSessionSubtitle: 'This phone keeps the current desktop session until you clear or replace it.',
        tokenLabel: 'Token',
        tokenIssued: 'issued',
        tokenMissing: 'not issued',
        tokenIdLabel: 'Token id',
        tokenIdMissing: 'not issued yet',
        scopesLabel: 'Scopes',
        scopesMissing: 'none',
        advancedTitle: 'Advanced Connection Options',
        advancedSubtitle: 'Open these only when QR pairing is unavailable or when you need manual debugging. They stay collapsed to keep Device fast.',
        showAdvanced: 'Show Advanced Options',
        hideAdvanced: 'Hide Advanced Options',
        gatewayTitle: 'Gateway Endpoint',
        gatewaySubtitle: 'Use this only when QR pairing needs a manual network fallback.',
        resolvedPort: 'Resolved port',
        saveConnection: 'Save Connection',
        syncModeTitle: 'Sync Mode',
        syncModeSubtitle: 'Choose how this paired device refreshes desktop state.',
        realtimeOption: 'Realtime Stream',
        pollingOption: 'Polling Only',
        currentSync: 'Current sync',
        currentSyncRealtime: 'Subscription stream for the active terminal',
        currentSyncPolling: 'Timer-based polling only',
        pollingInterval: 'Fallback / polling interval',
        manualPairingTitle: 'Manual Pairing',
        manualPairingSubtitle: 'Fallback only for cases where QR scanning is unavailable.',
        requestedScopes: 'Requested scopes',
        beginPairing: 'Begin Pairing',
        exchangePairing: 'Exchange Pairing',
        resetTitle: 'Reset Device',
        resetSubtitle: 'Remove the saved desktop session from this phone.',
        clearSavedSession: 'Clear Saved Session',
        scannerTitle: 'Scan Pairing QR',
        scannerSubtitle: 'Point the rear camera at the desktop pairing code.',
        close: 'Close',
        cameraPermissionRequiredTitle: 'Camera Permission Required',
        cameraPermissionRequiredMessage: 'Camera permission is required to scan the pairing QR.',
        pairingQrErrorTitle: 'Pairing QR Error',
        qrScannerErrorTitle: 'QR Scanner Error',
        unexpectedDeviceError: 'Unexpected device error',
    };
}

export default function GhoDexGatewayScreen() {
    const { theme } = useUnistyles();
    const router = useRouter();
    const checkScannerPermissions = useCheckScannerPermissions();
    const initialSession = React.useMemo(() => getCachedStoredSession(), []);
    const copy = React.useMemo(() => getGatewayCopy(), []);
    const [busyAction, setBusyAction] = React.useState<BusyAction>(null);
    const [errorMessage, setErrorMessage] = React.useState<string | null>(null);
    const [embeddedScannerVisible, setEmbeddedScannerVisible] = React.useState(false);
    const [advancedVisible, setAdvancedVisible] = React.useState(false);
    const [session, setSession] = React.useState<StoredSession>(initialSession);
    const [host, setHost] = React.useState(initialSession.host);
    const [portText, setPortText] = React.useState(String(initialSession.port));
    const [liveUpdatesEnabled, setLiveUpdatesEnabled] = React.useState(initialSession.liveUpdatesEnabled);
    const [pollIntervalMs, setPollIntervalMs] = React.useState(initialSession.pollIntervalMs);
    const embeddedScannerLockedRef = React.useRef(false);

    useFocusEffect(React.useCallback(() => {
        let active = true;
        const openedAt = recordScreenStarted('device');
        const task = InteractionManager.runAfterInteractions(() => {
            void (async () => {
                const stored = await loadStoredSession();
                if (!active) {
                    return;
                }

                setSession(stored);
                setHost(stored.host);
                setPortText(String(stored.port));
                setLiveUpdatesEnabled(stored.liveUpdatesEnabled);
                setPollIntervalMs(stored.pollIntervalMs);
                recordScreenReady('device', openedAt);
            })();
        });

        return () => {
            active = false;
            task.cancel();
        };
    }, []));

    const resolvedHost = host.trim() || INITIAL_GATEWAY_SESSION.host;
    const resolvedPort = sanitizePort(portText);
    const sanitizedPollIntervalMs = sanitizePollInterval(pollIntervalMs);
    const paired = !!session.authToken.trim();
    const buildSession = React.useCallback((base: StoredSession, delta?: Partial<StoredSession>): StoredSession => ({
        ...base,
        host: resolvedHost,
        port: resolvedPort,
        liveUpdatesEnabled,
        pollIntervalMs: sanitizedPollIntervalMs,
        ...delta,
    }), [liveUpdatesEnabled, resolvedHost, resolvedPort, sanitizedPollIntervalMs]);

    const runAction = React.useCallback(async (action: BusyAction, task: () => Promise<void>) => {
        setBusyAction(action);
        setErrorMessage(null);
        try {
            await task();
        } catch (error) {
            const message = error instanceof Error ? error.message : copy.unexpectedDeviceError;
            setErrorMessage(message);
        } finally {
            setBusyAction(null);
        }
    }, [copy.unexpectedDeviceError]);

    const dismissEmbeddedScanner = React.useCallback(() => {
        embeddedScannerLockedRef.current = false;
        setEmbeddedScannerVisible(false);
    }, []);

    const openEmbeddedScanner = React.useCallback(async () => {
        if (!(await checkScannerPermissions({ requireCameraOnAndroid: true }))) {
            const message = copy.cameraPermissionRequiredMessage;
            setErrorMessage(message);
            Alert.alert(copy.cameraPermissionRequiredTitle, message);
            return false;
        }

        embeddedScannerLockedRef.current = false;
        setEmbeddedScannerVisible(true);
        return true;
    }, [checkScannerPermissions, copy.cameraPermissionRequiredMessage, copy.cameraPermissionRequiredTitle]);

    const handleSaveConnectionSettings = React.useCallback(() => {
        void runAction('save', async () => {
            const current = await loadStoredSession();
            const nextSession = buildSession(current);
            await saveStoredSession(nextSession);
            setSession(nextSession);
        });
    }, [buildSession, runAction]);

    const handleBeginPairing = React.useCallback(() => {
        void runAction('begin', async () => {
            const result = await pairingBegin({
                host: resolvedHost,
                port: resolvedPort,
                client: 'ghodex-remote-client',
                deviceId: session.deviceId,
                deviceLabel: session.deviceLabel,
                requestedScopes: session.requestedScopes,
            });

            const nextSession = buildSession(session, {
                pairingCode: result.pairingCode,
                scopes: result.scopes.length > 0 ? result.scopes : session.scopes,
            });
            await saveStoredSession(nextSession);
            setSession(nextSession);
        });
    }, [buildSession, resolvedHost, resolvedPort, runAction, session]);

    const handleExchangePairing = React.useCallback(() => {
        void runAction('exchange', async () => {
            const result = await pairingExchange({
                host: resolvedHost,
                port: resolvedPort,
                pairingCode: session.pairingCode,
            });

            const nextSession = buildSession(
                applyPairingExchangeToSession(
                    session,
                    {
                        host: resolvedHost,
                        port: resolvedPort,
                        pairingCode: session.pairingCode,
                    },
                    result,
                ),
            );
            await saveStoredSession(nextSession);
            setSession(nextSession);
            router.replace('/');
        });
    }, [buildSession, resolvedHost, resolvedPort, router, runAction, session]);

    const handleGatewayPairingQr = React.useCallback((rawPayload: string) => {
        let payload: ReturnType<typeof parseGatewayPairingQrPayload>;
        try {
            payload = parseGatewayPairingQrPayload(rawPayload);
        } catch (error) {
            const message = error instanceof Error ? error.message : 'Unable to parse pairing QR';
            setErrorMessage(message);
            Alert.alert(copy.pairingQrErrorTitle, message);
            return;
        }

        void runAction('scan', async () => {
            const exchange = await pairingExchange({
                host: payload.host,
                port: payload.port,
                pairingCode: payload.pairingCode,
            });

            const nextSession = buildSession(
                applyPairingExchangeToSession(
                    session,
                    {
                        host: payload.host,
                        port: payload.port,
                        pairingCode: payload.pairingCode,
                    },
                    exchange,
                ),
            );
            setHost(payload.host);
            setPortText(String(payload.port));
            await saveStoredSession(nextSession);
            setSession(nextSession);
            router.replace('/');
        });
    }, [buildSession, copy.pairingQrErrorTitle, router, runAction, session]);

    const handleScanPairingQr = React.useCallback(async () => {
        setErrorMessage(null);

        if (!CameraView.isModernBarcodeScannerAvailable) {
            await openEmbeddedScanner();
            return;
        }

        if (!(await checkScannerPermissions())) {
            const message = copy.cameraPermissionRequiredMessage;
            setErrorMessage(message);
            Alert.alert(copy.cameraPermissionRequiredTitle, message);
            return;
        }

        try {
            await CameraView.launchScanner({
                barcodeTypes: ['qr'],
            });
        } catch {
            await openEmbeddedScanner();
        }
    }, [checkScannerPermissions, copy.cameraPermissionRequiredMessage, copy.cameraPermissionRequiredTitle, openEmbeddedScanner]);

    const handleEmbeddedBarcodeScanned = React.useCallback(({ data }: { data: string }) => {
        if (embeddedScannerLockedRef.current) {
            return;
        }

        const payload = typeof data === 'string' ? data.trim() : String(data ?? '').trim();
        if (!payload) {
            return;
        }

        embeddedScannerLockedRef.current = true;
        setEmbeddedScannerVisible(false);
        handleGatewayPairingQr(payload);
    }, [handleGatewayPairingQr]);

    const handleEmbeddedScannerMountError = React.useCallback(({ message }: { message: string }) => {
        dismissEmbeddedScanner();
        setErrorMessage(message);
        Alert.alert(copy.qrScannerErrorTitle, message);
    }, [copy.qrScannerErrorTitle, dismissEmbeddedScanner]);

    const handleClear = React.useCallback(() => {
        void runAction('clear', async () => {
            await clearStoredSession();
            setSession(INITIAL_GATEWAY_SESSION);
            setHost(INITIAL_GATEWAY_SESSION.host);
            setPortText(String(INITIAL_GATEWAY_SESSION.port));
            setLiveUpdatesEnabled(INITIAL_GATEWAY_SESSION.liveUpdatesEnabled);
            setPollIntervalMs(INITIAL_GATEWAY_SESSION.pollIntervalMs);
        });
    }, [runAction]);

    React.useEffect(() => {
        if (!CameraView.isModernBarcodeScannerAvailable) {
            return;
        }

        const subscription = CameraView.onModernBarcodeScanned(async (event) => {
            const payload = typeof event.data === 'string' ? event.data : String(event.data ?? '');
            await CameraView.dismissScanner();
            handleGatewayPairingQr(payload);
        });

        return () => {
            subscription.remove();
        };
    }, [handleGatewayPairingQr]);

    return (
        <>
            <ScrollView style={styles.screen} contentContainerStyle={styles.content}>
                <SurfaceCard
                    title={copy.screenTitle}
                    subtitle={copy.screenSubtitle}
                >
                    <View style={styles.pillRow}>
                        <InfoPill icon="radio-outline" label={`${resolvedHost}:${resolvedPort}`} />
                        <InfoPill icon="key-outline" label={paired ? copy.paired : copy.awaitingPairing} />
                        <InfoPill icon="sync-outline" label={liveUpdatesEnabled ? copy.realtimeStream : copy.polling(sanitizedPollIntervalMs)} />
                    </View>
                    <View style={styles.actions}>
                        <ActionButton
                            busy={busyAction === 'scan'}
                            label={paired ? copy.scanToReplace : copy.scanPairingQr}
                            onPress={() => {
                                void handleScanPairingQr();
                            }}
                        />
                        <ActionButton kind="secondary" label={copy.backToWorkspace} onPress={() => router.replace('/')} />
                    </View>
                </SurfaceCard>

                {errorMessage ? (
                    <View style={styles.errorBox}>
                        <Text style={styles.errorTitle}>{copy.deviceErrorTitle}</Text>
                        <Text style={styles.errorText}>{errorMessage}</Text>
                    </View>
                ) : null}

                <SurfaceCard
                    title={copy.savedSessionTitle}
                    subtitle={copy.savedSessionSubtitle}
                >
                    <SectionValue label={copy.tokenLabel} mono value={paired ? copy.tokenIssued : copy.tokenMissing} />
                    <SectionValue label={copy.tokenIdLabel} mono value={session.tokenId || copy.tokenIdMissing} />
                    <SectionValue label={copy.scopesLabel} mono value={session.scopes.length > 0 ? session.scopes.join(', ') : copy.scopesMissing} />
                </SurfaceCard>

                <SurfaceCard
                    title={copy.advancedTitle}
                    subtitle={copy.advancedSubtitle}
                >
                    <View style={styles.actions}>
                        <ActionButton
                            kind="secondary"
                            label={advancedVisible ? copy.hideAdvanced : copy.showAdvanced}
                            onPress={() => setAdvancedVisible((current) => !current)}
                        />
                    </View>
                </SurfaceCard>

                {advancedVisible ? (
                    <>
                        <SurfaceCard
                            title={copy.gatewayTitle}
                            subtitle={copy.gatewaySubtitle}
                        >
                            <TextInput
                                autoCapitalize="none"
                                autoCorrect={false}
                                onChangeText={setHost}
                                placeholder="127.0.0.1"
                                placeholderTextColor={theme.colors.input.placeholder}
                                style={styles.input}
                                value={host}
                            />
                            <TextInput
                                autoCapitalize="none"
                                autoCorrect={false}
                                inputMode="numeric"
                                keyboardType="number-pad"
                                onChangeText={setPortText}
                                placeholder="19527"
                                placeholderTextColor={theme.colors.input.placeholder}
                                style={styles.input}
                                value={portText}
                            />
                            <SectionValue label={copy.resolvedPort} mono value={String(resolvedPort)} />
                            <View style={styles.actions}>
                                <ActionButton busy={busyAction === 'save'} label={copy.saveConnection} onPress={handleSaveConnectionSettings} />
                            </View>
                        </SurfaceCard>

                        <SurfaceCard
                            title={copy.syncModeTitle}
                            subtitle={copy.syncModeSubtitle}
                        >
                            <View style={styles.optionRow}>
                                <Pressable
                                    onPress={() => setLiveUpdatesEnabled(true)}
                                    style={({ pressed }) => [
                                        styles.optionChip,
                                        liveUpdatesEnabled ? styles.optionChipActive : null,
                                        pressed ? styles.optionChipPressed : null,
                                    ]}
                                >
                                    <Text style={[styles.optionChipText, liveUpdatesEnabled ? styles.optionChipTextActive : null]}>
                                        {copy.realtimeOption}
                                    </Text>
                                </Pressable>
                                <Pressable
                                    onPress={() => setLiveUpdatesEnabled(false)}
                                    style={({ pressed }) => [
                                        styles.optionChip,
                                        !liveUpdatesEnabled ? styles.optionChipActive : null,
                                        pressed ? styles.optionChipPressed : null,
                                    ]}
                                >
                                    <Text style={[styles.optionChipText, !liveUpdatesEnabled ? styles.optionChipTextActive : null]}>
                                        {copy.pollingOption}
                                    </Text>
                                </Pressable>
                            </View>

                            <SectionValue
                                label={copy.currentSync}
                                value={liveUpdatesEnabled ? copy.currentSyncRealtime : copy.currentSyncPolling}
                            />

                            <Text style={styles.optionLabel}>{copy.pollingInterval}</Text>
                            <View style={styles.optionRow}>
                                {POLL_INTERVAL_OPTIONS.map((value) => (
                                    <Pressable
                                        key={value}
                                        onPress={() => setPollIntervalMs(value)}
                                        style={({ pressed }) => [
                                            styles.intervalChip,
                                            pollIntervalMs === value ? styles.intervalChipActive : null,
                                            pressed ? styles.optionChipPressed : null,
                                        ]}
                                    >
                                        <Text style={[styles.intervalChipText, pollIntervalMs === value ? styles.intervalChipTextActive : null]}>
                                            {value}ms
                                        </Text>
                                    </Pressable>
                                ))}
                            </View>
                        </SurfaceCard>

                        <SurfaceCard
                            title={copy.manualPairingTitle}
                            subtitle={copy.manualPairingSubtitle}
                        >
                            <SectionValue label={copy.requestedScopes} mono value={session.requestedScopes.join(', ')} />
                            <View style={styles.actions}>
                                <ActionButton busy={busyAction === 'begin'} kind="secondary" label={copy.beginPairing} onPress={handleBeginPairing} />
                            </View>
                            <TextInput
                                autoCapitalize="characters"
                                autoCorrect={false}
                                onChangeText={(value) => setSession((current) => ({ ...current, pairingCode: value.trim() }))}
                                placeholder="PAIR-123"
                                placeholderTextColor={theme.colors.input.placeholder}
                                style={styles.input}
                                value={session.pairingCode}
                            />
                            <View style={styles.actions}>
                                <ActionButton busy={busyAction === 'exchange'} label={copy.exchangePairing} onPress={handleExchangePairing} />
                            </View>
                        </SurfaceCard>

                        <SurfaceCard
                            title={copy.resetTitle}
                            subtitle={copy.resetSubtitle}
                        >
                            <View style={styles.actions}>
                                <ActionButton busy={busyAction === 'clear'} kind="secondary" label={copy.clearSavedSession} onPress={handleClear} />
                            </View>
                        </SurfaceCard>
                    </>
                ) : null}
            </ScrollView>

            <Modal
                animationType="slide"
                onRequestClose={dismissEmbeddedScanner}
                presentationStyle="fullScreen"
                visible={embeddedScannerVisible}
            >
                <View style={styles.scannerScreen}>
                    <View style={styles.scannerHeader}>
                        <View style={styles.scannerHeaderCopy}>
                            <Text style={styles.scannerTitle}>{copy.scannerTitle}</Text>
                            <Text style={styles.scannerSubtitle}>{copy.scannerSubtitle}</Text>
                        </View>
                        <Pressable
                            onPress={dismissEmbeddedScanner}
                            style={({ pressed }) => [styles.scannerCloseButton, pressed ? styles.optionChipPressed : null]}
                        >
                            <Text style={styles.scannerCloseText}>{copy.close}</Text>
                        </Pressable>
                    </View>

                    <View style={styles.scannerPreviewShell}>
                        <CameraView
                            barcodeScannerSettings={{ barcodeTypes: ['qr'] }}
                            facing="back"
                            onBarcodeScanned={handleEmbeddedBarcodeScanned}
                            onMountError={handleEmbeddedScannerMountError}
                            style={styles.scannerPreview}
                        />
                        <View pointerEvents="none" style={styles.scannerGuide}>
                            <View style={styles.scannerGuideFrame} />
                        </View>
                    </View>
                </View>
            </Modal>
        </>
    );
}

const styles = StyleSheet.create((theme) => ({
    screen: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
    },
    content: {
        padding: 16,
        gap: 16,
    },
    pillRow: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        gap: 8,
    },
    input: {
        backgroundColor: theme.colors.input.background,
        borderWidth: 1,
        borderColor: theme.colors.divider,
        borderRadius: 14,
        paddingHorizontal: 14,
        paddingVertical: 12,
        color: theme.colors.input.text,
        fontSize: 16,
    },
    actions: {
        flexDirection: 'row',
        gap: 12,
    },
    optionLabel: {
        color: theme.colors.groupped.sectionTitle,
        fontSize: 12,
        fontWeight: '700',
        textTransform: 'uppercase',
        letterSpacing: 0.6,
    },
    optionRow: {
        flexDirection: 'row',
        flexWrap: 'wrap',
        gap: 10,
    },
    optionChip: {
        borderRadius: 14,
        paddingHorizontal: 14,
        paddingVertical: 11,
        backgroundColor: theme.colors.surfaceHigh,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    optionChipActive: {
        backgroundColor: theme.colors.button.primary.background,
        borderColor: theme.colors.button.primary.background,
    },
    optionChipPressed: {
        opacity: 0.84,
    },
    optionChipText: {
        color: theme.colors.text,
        fontSize: 14,
        fontWeight: '700',
    },
    optionChipTextActive: {
        color: theme.colors.button.primary.tint,
    },
    intervalChip: {
        borderRadius: 999,
        paddingHorizontal: 12,
        paddingVertical: 9,
        backgroundColor: theme.colors.surface,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    intervalChipActive: {
        backgroundColor: theme.colors.button.primary.background,
        borderColor: theme.colors.button.primary.background,
    },
    intervalChipText: {
        color: theme.colors.text,
        fontSize: 13,
        fontWeight: '700',
    },
    intervalChipTextActive: {
        color: theme.colors.button.primary.tint,
    },
    errorBox: {
        backgroundColor: theme.colors.box.error.background,
        borderColor: theme.colors.box.error.border,
        borderRadius: 14,
        borderWidth: 1,
        padding: 12,
        gap: 4,
        marginHorizontal: 16,
    },
    errorTitle: {
        color: theme.colors.box.error.text,
        fontSize: 13,
        fontWeight: '700',
    },
    errorText: {
        color: theme.colors.text,
        fontSize: 14,
        lineHeight: 20,
    },
    scannerScreen: {
        flex: 1,
        backgroundColor: theme.colors.groupped.background,
        paddingHorizontal: 18,
        paddingTop: 20,
        paddingBottom: 28,
        gap: 18,
    },
    scannerHeader: {
        flexDirection: 'row',
        alignItems: 'flex-start',
        justifyContent: 'space-between',
        gap: 12,
    },
    scannerHeaderCopy: {
        flex: 1,
        gap: 6,
    },
    scannerTitle: {
        color: theme.colors.text,
        fontSize: 24,
        fontWeight: '800',
    },
    scannerSubtitle: {
        color: theme.colors.textSecondary,
        fontSize: 14,
        lineHeight: 20,
    },
    scannerCloseButton: {
        backgroundColor: theme.colors.button.primary.background,
        borderRadius: 12,
        borderWidth: 1,
        borderColor: theme.colors.button.primary.background,
        paddingHorizontal: 14,
        paddingVertical: 10,
    },
    scannerCloseText: {
        color: theme.colors.button.primary.tint,
        fontSize: 14,
        fontWeight: '700',
    },
    scannerPreviewShell: {
        flex: 1,
        minHeight: 360,
        borderRadius: 28,
        overflow: 'hidden',
        backgroundColor: theme.colors.terminal.background,
        borderWidth: 1,
        borderColor: theme.colors.divider,
    },
    scannerPreview: {
        flex: 1,
    },
    scannerGuide: {
        ...StyleSheet.absoluteFillObject,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: theme.dark ? 'rgba(0, 0, 0, 0.28)' : 'rgba(255, 255, 255, 0.22)',
    },
    scannerGuideFrame: {
        width: '68%',
        aspectRatio: 1,
        borderRadius: 28,
        borderWidth: 3,
        borderColor: theme.colors.button.primary.background,
        backgroundColor: 'transparent',
    },
}));
