import { AgentInput } from '@/components/AgentInput';
import { layout } from '@/components/layout';
import {
    getAvailableModels,
    getAvailablePermissionModes,
    getDefaultModelKey,
    getDefaultPermissionModeKey,
    resolveCurrentOption,
} from '@/components/modelModeOptions';
import { getSuggestions } from '@/components/autocomplete/suggestions';
import { ChatHeaderView } from '@/components/ChatHeaderView';
import { ChatList } from '@/components/ChatList';
import { Deferred } from '@/components/Deferred';
import { EmptyMessages } from '@/components/EmptyMessages';
import { SessionActionsAnchor, SessionActionsPopover } from '@/components/SessionActionsPopover';
import { VoiceAssistantStatusBar } from '@/components/VoiceAssistantStatusBar';
import { useDraft } from '@/hooks/useDraft';
import { useSessionQuickActions } from '@/hooks/useSessionQuickActions';
import { Modal } from '@/modal';
import { voiceHooks } from '@/realtime/hooks/voiceHooks';
import { startRealtimeSession, stopRealtimeSession } from '@/realtime/RealtimeSession';
import { gitStatusSync } from '@/sync/gitStatusSync';
import { sessionAbort } from '@/sync/ops';
import { storage, useIsDataReady, useLocalSetting, useRealtimeStatus, useSessionMessages, useSessionUsage, useSetting } from '@/sync/storage';
import { useSession } from '@/sync/storage';
import { Session } from '@/sync/storageTypes';
import { sync } from '@/sync/sync';
import { t } from '@/text';
import { tracking, trackMessageSent } from '@/track';
import { isRunningOnMac } from '@/utils/platform';
import { useDeviceType, useHeaderHeight, useIsLandscape, useIsTablet } from '@/utils/responsive';
import { formatLastSeen, formatPathRelativeToHome, getResumeCommand, getSessionAvatarId, getSessionName, useSessionStatus } from '@/utils/sessionUtils';
import { isVersionSupported, MINIMUM_CLI_VERSION } from '@/utils/versionUtils';
import * as Clipboard from 'expo-clipboard';
import { Ionicons } from '@expo/vector-icons';
import { useRouter } from 'expo-router';
import * as React from 'react';
import { useMemo } from 'react';
import { ActivityIndicator, Platform, Pressable, ScrollView, Text, View } from 'react-native';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { useUnistyles } from 'react-native-unistyles';
import type { ModelMode, PermissionMode } from '@/components/PermissionModeSelector';

export const SessionView = React.memo((props: { id: string }) => {
    const sessionId = props.id;
    const router = useRouter();
    const session = useSession(sessionId);
    const isDataReady = useIsDataReady();
    const { theme } = useUnistyles();
    const safeArea = useSafeAreaInsets();
    const isLandscape = useIsLandscape();
    const deviceType = useDeviceType();
    const headerHeight = useHeaderHeight();
    const realtimeStatus = useRealtimeStatus();
    const isTablet = useIsTablet();
    const [sessionActionsAnchor, setSessionActionsAnchor] = React.useState<SessionActionsAnchor | null>(null);

    // Compute header props based on session state
    const headerProps = useMemo(() => {
        if (!isDataReady) {
            // Loading state - show empty header
            return {
                title: '',
                subtitle: undefined,
                avatarId: undefined,
                onAvatarPress: undefined,
                isConnected: false,
                flavor: null
            };
        }

        if (!session) {
            // Deleted state - show deleted message in header
            return {
                title: t('errors.sessionDeleted'),
                subtitle: undefined,
                avatarId: undefined,
                onAvatarPress: undefined,
                isConnected: false,
                flavor: null
            };
        }

        // Normal state - show session info
        const isConnected = session.presence === 'online';
        return {
            title: getSessionName(session),
            subtitle: session.metadata?.path ? formatPathRelativeToHome(session.metadata.path, session.metadata?.homeDir) : undefined,
            avatarId: getSessionAvatarId(session),
            onAvatarPress: () => router.push(`/session/${sessionId}/info`),
            isConnected: isConnected,
            flavor: session.metadata?.flavor || null,
            tintColor: isConnected ? '#000' : '#8E8E93'
        };
    }, [session, isDataReady, sessionId, router]);

    return (
        <>
            {/* Status bar shadow for landscape mode */}
            {isLandscape && deviceType === 'phone' && (
                <View style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    right: 0,
                    height: safeArea.top,
                    backgroundColor: theme.colors.surface,
                    zIndex: 1000,
                    shadowColor: theme.colors.shadow.color,
                    shadowOffset: {
                        width: 0,
                        height: 2,
                    },
                    shadowOpacity: theme.colors.shadow.opacity,
                    shadowRadius: 3,
                    elevation: 5,
                }} />
            )}

            {/* Header - always shown on desktop/Mac, hidden in landscape mode only on actual phones */}
            {!(isLandscape && deviceType === 'phone' && Platform.OS !== 'web') && (
                <View style={{
                    position: 'absolute',
                    top: 0,
                    left: 0,
                    right: 0,
                    zIndex: 1000
                }}>
                    <ChatHeaderView
                        {...headerProps}
                        onBackPress={() => router.back()}
                        avatarMenuExpanded={Platform.OS === 'web' && !!sessionActionsAnchor}
                        avatarMenuSession={session}
                        onAfterAvatarArchive={() => {
                            setSessionActionsAnchor(null);
                            router.replace('/');
                        }}
                        onAfterAvatarDelete={() => {
                            setSessionActionsAnchor(null);
                            router.replace('/');
                        }}
                        onAvatarMenuRequest={Platform.OS === 'web' && session ? setSessionActionsAnchor : undefined}
                    />
                    {/* Voice status bar below header - not on tablet (shown in sidebar) */}
                    {!isTablet && realtimeStatus !== 'disconnected' && (
                        <VoiceAssistantStatusBar variant="full" />
                    )}
                </View>
            )}

            {/* Content based on state */}
            <View style={{ flex: 1, paddingTop: !(isLandscape && deviceType === 'phone' && Platform.OS !== 'web') ? safeArea.top + headerHeight + (!isTablet && realtimeStatus !== 'disconnected' ? 48 : 0) : 0 }}>
                {!isDataReady ? (
                    // Loading state
                    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
                        <ActivityIndicator size="small" color={theme.colors.textSecondary} />
                    </View>
                ) : !session ? (
                    // Deleted state
                    <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
                        <Ionicons name="trash-outline" size={48} color={theme.colors.textSecondary} />
                        <Text style={{ color: theme.colors.text, fontSize: 20, marginTop: 16, fontWeight: '600' }}>{t('errors.sessionDeleted')}</Text>
                        <Text style={{ color: theme.colors.textSecondary, fontSize: 15, marginTop: 8, textAlign: 'center', paddingHorizontal: 32 }}>{t('errors.sessionDeletedDescription')}</Text>
                    </View>
                ) : (
                    // Normal session view
                    <SessionViewLoaded key={sessionId} sessionId={sessionId} session={session} />
                )}
            </View>
            {Platform.OS === 'web' && session && (
                <SessionActionsPopover
                    anchor={sessionActionsAnchor}
                    onAfterArchive={() => {
                        setSessionActionsAnchor(null);
                        router.replace('/');
                    }}
                    onAfterDelete={() => {
                        setSessionActionsAnchor(null);
                        router.replace('/');
                    }}
                    onClose={() => setSessionActionsAnchor(null)}
                    session={session}
                    visible={!!sessionActionsAnchor}
                />
            )}
        </>
    );
});


function SessionViewLoaded({ sessionId, session }: { sessionId: string, session: Session }) {
    const { theme } = useUnistyles();
    const router = useRouter();
    const safeArea = useSafeAreaInsets();
    const isLandscape = useIsLandscape();
    const deviceType = useDeviceType();
    const isTablet = useIsTablet();
    const [message, setMessage] = React.useState('');
    const realtimeStatus = useRealtimeStatus();
    const { messages, isLoaded } = useSessionMessages(sessionId);
    const acknowledgedCliVersions = useLocalSetting('acknowledgedCliVersions');
    const sessionInputHorizontalPadding = Platform.OS === 'web' || isRunningOnMac() || isTablet ? 12 : 8;

    // Check if CLI version is outdated and not already acknowledged
    const cliVersion = session.metadata?.version;
    const machineId = session.metadata?.machineId;
    const isCliOutdated = cliVersion && !isVersionSupported(cliVersion, MINIMUM_CLI_VERSION);
    const isAcknowledged = machineId && acknowledgedCliVersions[machineId] === cliVersion;
    const shouldShowCliWarning = isCliOutdated && !isAcknowledged;
    const flavor = session.metadata?.flavor;
    const availableModels = React.useMemo(() => (
        getAvailableModels(flavor, session.metadata, t)
    ), [flavor, session.metadata]);
    const availableModes = React.useMemo(() => (
        getAvailablePermissionModes(flavor, session.metadata, t)
    ), [flavor, session.metadata]);

    const permissionMode = React.useMemo<PermissionMode | null>(() => (
        resolveCurrentOption(availableModes, [
            session.permissionMode,
            session.metadata?.currentOperatingModeCode,
            getDefaultPermissionModeKey(flavor),
        ])
    ), [availableModes, session.permissionMode, session.metadata?.currentOperatingModeCode, flavor]);

    const modelMode = React.useMemo<ModelMode | null>(() => (
        resolveCurrentOption(availableModels, [
            session.modelMode,
            session.metadata?.currentModelCode,
            getDefaultModelKey(flavor),
        ])
    ), [availableModels, session.modelMode, session.metadata?.currentModelCode, flavor]);
    const sessionStatus = useSessionStatus(session);
    const sessionUsage = useSessionUsage(sessionId);
    const alwaysShowContextSize = useSetting('alwaysShowContextSize');
    const experiments = useSetting('experiments');
    const expResumeSession = useSetting('expResumeSession');
    const resumeCommand = getResumeCommand(session);
    const {
        canCopySessionMetadata,
        canResume,
        canShowResume,
        copySessionMetadata,
        openDetails,
        resumeSession,
        resumeSessionSubtitle,
        resumingSession,
    } = useSessionQuickActions(session);

    // Use draft hook for auto-saving message drafts
    const { clearDraft } = useDraft(sessionId, message, setMessage);

    // Handle dismissing CLI version warning
    const handleDismissCliWarning = React.useCallback(() => {
        if (machineId && cliVersion) {
            storage.getState().applyLocalSettings({
                acknowledgedCliVersions: {
                    ...acknowledgedCliVersions,
                    [machineId]: cliVersion
                }
            });
        }
    }, [machineId, cliVersion, acknowledgedCliVersions]);

    // Function to update permission mode
    const updatePermissionMode = React.useCallback((mode: PermissionMode) => {
        storage.getState().updateSessionPermissionMode(sessionId, mode.key);
    }, [sessionId]);

    const updateModelMode = React.useCallback((mode: ModelMode) => {
        storage.getState().updateSessionModelMode(sessionId, mode.key);
    }, [sessionId]);

    // Handle microphone button press - memoized to prevent button flashing
    const handleMicrophonePress = React.useCallback(async () => {
        if (realtimeStatus === 'connecting') {
            return; // Prevent actions during transitions
        }
        if (realtimeStatus === 'disconnected' || realtimeStatus === 'error') {
            try {
                const initialPrompt = voiceHooks.onVoiceStarted(sessionId);
                await startRealtimeSession(sessionId, initialPrompt);
                tracking?.capture('voice_session_started', { sessionId });
            } catch (error) {
                console.error('Failed to start realtime session:', error);
                Modal.alert(t('common.error'), t('errors.voiceSessionFailed'));
                tracking?.capture('voice_session_error', { error: error instanceof Error ? error.message : 'Unknown error' });
            }
        } else if (realtimeStatus === 'connected') {
            await stopRealtimeSession();
            tracking?.capture('voice_session_stopped');

            // Notify voice assistant about voice session stop
            voiceHooks.onVoiceStopped();
        }
    }, [realtimeStatus, sessionId]);

    // Memoize mic button state to prevent flashing during chat transitions
    const micButtonState = useMemo(() => ({
        onMicPress: handleMicrophonePress,
        isMicActive: realtimeStatus === 'connected' || realtimeStatus === 'connecting'
    }), [handleMicrophonePress, realtimeStatus]);

    // Trigger session visibility and initialize git status sync
    React.useLayoutEffect(() => {

        // Trigger session sync
        sync.onSessionVisible(sessionId);


        // Initialize git status sync for this session
        gitStatusSync.getSync(sessionId);
    }, [sessionId, realtimeStatus]);

    let content = (
        <>
            <Deferred>
                {messages.length > 0 && (
                    <ChatList session={session} topInset={12} bottomInset={8} />
                )}
            </Deferred>
        </>
    );
    const placeholder = messages.length === 0 ? (
        <>
            {isLoaded ? (
                <EmptyMessages session={session} />
            ) : (
                <ActivityIndicator size="small" color={theme.colors.textSecondary} />
            )}
        </>
    ) : null;

    const input = sessionStatus.isConnected ? (
        <AgentInput
            placeholder={t('session.inputPlaceholder')}
            value={message}
            onChangeText={setMessage}
            sessionId={sessionId}
            permissionMode={permissionMode}
            onPermissionModeChange={updatePermissionMode}
            availableModes={availableModes}
            modelMode={modelMode}
            availableModels={availableModels}
            onModelModeChange={updateModelMode}
            metadata={session.metadata}
            connectionStatus={{
                text: sessionStatus.statusText,
                color: sessionStatus.statusColor,
                dotColor: sessionStatus.statusDotColor,
                isPulsing: sessionStatus.isPulsing
            }}
            onSend={() => {
                if (message.trim()) {
                    setMessage('');
                    clearDraft();
                    sync.sendMessage(sessionId, message);
                    trackMessageSent();
                }
            }}
            onMicPress={micButtonState.onMicPress}
            isMicActive={micButtonState.isMicActive}
            onAbort={() => sessionAbort(sessionId)}
            showAbortButton={sessionStatus.state === 'thinking' || sessionStatus.state === 'waiting'}
            onFileViewerPress={experiments ? () => router.push(`/session/${sessionId}/files`) : undefined}
            autocompletePrefixes={['@', '/']}
            autocompleteSuggestions={(query) => getSuggestions(sessionId, query)}
            usageData={sessionUsage ? {
                inputTokens: sessionUsage.inputTokens,
                outputTokens: sessionUsage.outputTokens,
                cacheCreation: sessionUsage.cacheCreation,
                cacheRead: sessionUsage.cacheRead,
                contextSize: sessionUsage.contextSize
            } : session.latestUsage ? {
                inputTokens: session.latestUsage.inputTokens,
                outputTokens: session.latestUsage.outputTokens,
                cacheCreation: session.latestUsage.cacheCreation,
                cacheRead: session.latestUsage.cacheRead,
                contextSize: session.latestUsage.contextSize
            } : undefined}
            alwaysShowContextSize={alwaysShowContextSize}
        />
    ) : canShowResume && expResumeSession ? (
        <CenteredInputWidth horizontalPadding={sessionInputHorizontalPadding}>
            <View style={{
                paddingHorizontal: 16,
                paddingTop: 12,
                paddingBottom: 10,
                gap: 10,
            }}>
                <Pressable
                    onPress={resumeSession}
                    style={{
                        minHeight: 48,
                        borderRadius: 14,
                        backgroundColor: canResume ? theme.colors.button.primary.background : theme.colors.surfaceHigh,
                        alignItems: 'center',
                        justifyContent: 'center',
                        flexDirection: 'row',
                        gap: 8,
                        opacity: resumingSession ? 0.7 : 1,
                    }}
                >
                    {resumingSession ? (
                        <ActivityIndicator size="small" color={canResume ? theme.colors.button.primary.tint : theme.colors.textSecondary} />
                    ) : (
                        <Ionicons
                            name="play-circle-outline"
                            size={18}
                            color={canResume ? theme.colors.button.primary.tint : theme.colors.textSecondary}
                        />
                    )}
                    <Text style={{
                        color: canResume ? theme.colors.button.primary.tint : theme.colors.textSecondary,
                        fontSize: 15,
                        fontWeight: '600',
                    }}>
                        {t('sessionInfo.resumeSession')}
                    </Text>
                </Pressable>
                <Text style={{
                    color: theme.colors.textSecondary,
                    fontSize: 13,
                    lineHeight: 18,
                    textAlign: 'center',
                    paddingHorizontal: 8,
                }}>
                    {resumeSessionSubtitle}
                </Text>
            </View>
        </CenteredInputWidth>
    ) : !sessionStatus.isConnected && resumeCommand ? (
        <CenteredInputWidth horizontalPadding={sessionInputHorizontalPadding}>
            <ResumeCommandHint command={resumeCommand} />
        </CenteredInputWidth>
    ) : null;

    const showContextRail = isTablet || Platform.OS === 'web' || isRunningOnMac();
    const usageSnapshot = sessionUsage ?? session.latestUsage ?? null;
    const sessionPath = session.metadata?.path
        ? formatPathRelativeToHome(session.metadata.path, session.metadata.homeDir)
        : null;
    const workspaceFlavor = session.metadata?.flavor ?? 'unknown';
    const updatedLabel = formatLastSeen(session.updatedAt, sessionStatus.isConnected);
    const createdLabel = new Date(session.createdAt).toLocaleString();
    const primaryStatusColor = sessionStatus.isConnected ? sessionStatus.statusDotColor : theme.colors.textSecondary;

    const conversationBody = messages.length > 0 ? (
        content
    ) : (
        <View style={{
            flex: 1,
            alignItems: 'center',
            justifyContent: 'center',
            paddingHorizontal: 24,
        }}>
            {placeholder}
        </View>
    );

    return (
        <>
            <View style={{
                flexBasis: 0,
                flexGrow: 1,
                paddingBottom: safeArea.bottom + ((isRunningOnMac() || Platform.OS === 'web') ? 8 : 0),
                paddingHorizontal: showContextRail ? 14 : 10,
                paddingTop: 8,
            }}>
                {!showContextRail && (
                    <View style={{
                        borderRadius: 22,
                        backgroundColor: theme.colors.surface,
                        borderWidth: 1,
                        borderColor: theme.colors.divider,
                        paddingHorizontal: 14,
                        paddingTop: 14,
                        paddingBottom: 12,
                        marginBottom: 10,
                        gap: 12,
                    }}>
                        <View style={{
                            flexDirection: 'row',
                            alignItems: 'center',
                            justifyContent: 'space-between',
                            gap: 12,
                        }}>
                            <View style={{ flex: 1, gap: 4 }}>
                                <Text style={{
                                    color: theme.colors.text,
                                    fontSize: 18,
                                    fontWeight: '700',
                                }}>
                                    {session.metadata?.summary?.text ?? getSessionName(session)}
                                </Text>
                                <Text style={{
                                    color: theme.colors.textSecondary,
                                    fontSize: 13,
                                    lineHeight: 18,
                                }} numberOfLines={2}>
                                    {sessionPath ?? 'No workspace path'}
                                </Text>
                            </View>
                            <SessionStatusBadge
                                color={primaryStatusColor}
                                text={sessionStatus.statusText}
                            />
                        </View>

                        <ScrollView
                            horizontal
                            showsHorizontalScrollIndicator={false}
                            contentContainerStyle={{ gap: 8, paddingRight: 12 }}
                        >
                            <SessionInfoPill icon="hardware-chip-outline" label={`Model ${modelMode?.name ?? 'Auto'}`} />
                            <SessionInfoPill icon="shield-outline" label={`Mode ${permissionMode?.name ?? 'Default'}`} />
                            <SessionInfoPill icon="sparkles-outline" label={workspaceFlavor} />
                            {session.metadata?.host ? <SessionInfoPill icon="desktop-outline" label={session.metadata.host} /> : null}
                            {session.metadata?.version ? <SessionInfoPill icon="code-slash-outline" label={`CLI ${session.metadata.version}`} /> : null}
                            {usageSnapshot?.contextSize ? <SessionInfoPill icon="layers-outline" label={`${formatCompactNumber(usageSnapshot.contextSize)} ctx`} /> : null}
                        </ScrollView>

                        <View style={{ flexDirection: 'row', flexWrap: 'wrap', gap: 10 }}>
                            <SessionActionChip
                                icon="information-circle-outline"
                                label="Details"
                                onPress={openDetails}
                            />
                            {experiments ? (
                                <SessionActionChip
                                    icon="folder-open-outline"
                                    label="Files"
                                    onPress={() => router.push(`/session/${sessionId}/files`)}
                                />
                            ) : null}
                            {canShowResume && expResumeSession ? (
                                <SessionActionChip
                                    disabled={!canResume || resumingSession}
                                    icon={resumingSession ? undefined : 'play-circle-outline'}
                                    label={resumingSession ? 'Resuming…' : 'Resume'}
                                    onPress={resumeSession}
                                />
                            ) : null}
                        </View>
                    </View>
                )}

                <View style={{
                    flex: 1,
                    flexDirection: showContextRail ? 'row' : 'column',
                    gap: 12,
                    minHeight: 0,
                }}>
                    <View style={{
                        flex: 1,
                        minWidth: 0,
                        borderRadius: 26,
                        backgroundColor: theme.colors.surface,
                        borderWidth: 1,
                        borderColor: theme.colors.divider,
                        overflow: 'hidden',
                    }}>
                        <View style={{
                            paddingHorizontal: 16,
                            paddingTop: 14,
                            paddingBottom: 12,
                            borderBottomWidth: 1,
                            borderBottomColor: theme.colors.divider,
                            gap: 12,
                        }}>
                            <View style={{
                                flexDirection: 'row',
                                alignItems: 'center',
                                justifyContent: 'space-between',
                                gap: 12,
                            }}>
                                <View style={{ flex: 1, gap: 5 }}>
                                    <Text style={{
                                        color: theme.colors.text,
                                        fontSize: 17,
                                        fontWeight: '700',
                                    }}>
                                        Conversation
                                    </Text>
                                    <Text style={{
                                        color: theme.colors.textSecondary,
                                        fontSize: 13,
                                        lineHeight: 18,
                                    }} numberOfLines={1}>
                                        {sessionPath ?? 'Waiting for workspace metadata'}
                                    </Text>
                                </View>
                                <SessionStatusBadge
                                    color={primaryStatusColor}
                                    text={sessionStatus.statusText}
                                />
                            </View>

                            <View style={{
                                flexDirection: 'row',
                                flexWrap: 'wrap',
                                gap: 8,
                            }}>
                                <SessionInfoPill icon="shield-outline" label={permissionMode?.name ?? 'Default mode'} />
                                <SessionInfoPill icon="hardware-chip-outline" label={modelMode?.name ?? 'Auto model'} />
                                <SessionInfoPill icon="time-outline" label={`Updated ${updatedLabel}`} />
                                {session.metadata?.host ? <SessionInfoPill icon="desktop-outline" label={session.metadata.host} /> : null}
                            </View>

                            {shouldShowCliWarning && !(isLandscape && deviceType === 'phone') && (
                                <Pressable
                                    onPress={handleDismissCliWarning}
                                    style={{
                                        backgroundColor: '#FFF3CD',
                                        borderRadius: 16,
                                        paddingHorizontal: 14,
                                        paddingVertical: 10,
                                        flexDirection: 'row',
                                        alignItems: 'center',
                                        gap: 8,
                                    }}
                                >
                                    <Ionicons name="warning-outline" size={16} color="#FF9500" />
                                    <Text style={{
                                        flex: 1,
                                        fontSize: 12,
                                        color: '#856404',
                                        fontWeight: '600',
                                    }}>
                                        {t('sessionInfo.cliVersionOutdated')}
                                    </Text>
                                    <Ionicons name="close" size={14} color="#856404" />
                                </Pressable>
                            )}

                            {!sessionStatus.isConnected && canShowResume && expResumeSession && (
                                <View style={{
                                    borderRadius: 18,
                                    backgroundColor: theme.colors.groupped.background,
                                    padding: 14,
                                    gap: 10,
                                }}>
                                    <Text style={{
                                        color: theme.colors.text,
                                        fontSize: 15,
                                        fontWeight: '700',
                                    }}>
                                        Resume this session
                                    </Text>
                                    <Text style={{
                                        color: theme.colors.textSecondary,
                                        fontSize: 13,
                                        lineHeight: 18,
                                    }}>
                                        {resumeSessionSubtitle}
                                    </Text>
                                    <View style={{ flexDirection: 'row', gap: 10, flexWrap: 'wrap' }}>
                                        <SessionActionChip
                                            disabled={!canResume || resumingSession}
                                            icon={resumingSession ? undefined : 'play-circle-outline'}
                                            label={resumingSession ? 'Resuming…' : 'Resume'}
                                            onPress={resumeSession}
                                            primary
                                        />
                                        {resumeCommand ? (
                                            <SessionActionChip
                                                icon="copy-outline"
                                                label="Copy Resume Cmd"
                                                onPress={async () => Clipboard.setStringAsync(resumeCommand)}
                                            />
                                        ) : null}
                                    </View>
                                </View>
                            )}
                        </View>

                        <View style={{ flex: 1, minHeight: 0 }}>
                            {conversationBody}
                        </View>

                        {input ? (
                            <View style={{
                                borderTopWidth: 1,
                                borderTopColor: theme.colors.divider,
                                backgroundColor: theme.colors.surface,
                            }}>
                                {input}
                            </View>
                        ) : null}
                    </View>

                    {showContextRail && (
                        <ScrollView
                            style={{
                                width: 320,
                                flexGrow: 0,
                                flexShrink: 0,
                                borderRadius: 26,
                                backgroundColor: theme.colors.surface,
                                borderWidth: 1,
                                borderColor: theme.colors.divider,
                            }}
                            contentContainerStyle={{
                                padding: 14,
                                gap: 12,
                            }}
                            showsVerticalScrollIndicator={false}
                        >
                            <SessionRailCard title="Session">
                                <SessionDataRow label="State" value={sessionStatus.statusText} />
                                <SessionDataRow label="Flavor" value={workspaceFlavor} />
                                <SessionDataRow label="Created" value={createdLabel} />
                                <SessionDataRow label="Updated" value={updatedLabel} />
                            </SessionRailCard>

                            <SessionRailCard title="Quick Actions">
                                <View style={{ gap: 10 }}>
                                    <SessionActionChip
                                        icon="information-circle-outline"
                                        label="Session Details"
                                        onPress={openDetails}
                                        primary
                                    />
                                    {experiments ? (
                                        <SessionActionChip
                                            icon="folder-open-outline"
                                            label="Open Files"
                                            onPress={() => router.push(`/session/${sessionId}/files`)}
                                        />
                                    ) : null}
                                    {canShowResume && expResumeSession ? (
                                        <SessionActionChip
                                            disabled={!canResume || resumingSession}
                                            icon={resumingSession ? undefined : 'play-circle-outline'}
                                            label={resumingSession ? 'Resuming…' : 'Resume Session'}
                                            onPress={resumeSession}
                                        />
                                    ) : null}
                                    {canCopySessionMetadata ? (
                                        <SessionActionChip
                                            icon="copy-outline"
                                            label="Copy Metadata"
                                            onPress={copySessionMetadata}
                                        />
                                    ) : null}
                                </View>
                            </SessionRailCard>

                            <SessionRailCard title="Workspace">
                                {sessionPath ? <SessionDataRow label="Path" mono value={sessionPath} /> : null}
                                {session.metadata?.host ? <SessionDataRow label="Host" value={session.metadata.host} /> : null}
                                {session.metadata?.os ? <SessionDataRow label="OS" value={session.metadata.os} /> : null}
                                {session.metadata?.version ? <SessionDataRow label="CLI" value={session.metadata.version} /> : null}
                                <SessionDataRow label="Model" value={modelMode?.name ?? 'Auto'} />
                                <SessionDataRow label="Mode" value={permissionMode?.name ?? 'Default'} />
                            </SessionRailCard>

                            {usageSnapshot ? (
                                <SessionRailCard title="Usage">
                                    <SessionDataRow label="Input" value={formatCompactNumber(usageSnapshot.inputTokens)} />
                                    <SessionDataRow label="Output" value={formatCompactNumber(usageSnapshot.outputTokens)} />
                                    <SessionDataRow label="Cache Read" value={formatCompactNumber(usageSnapshot.cacheRead)} />
                                    <SessionDataRow label="Cache Create" value={formatCompactNumber(usageSnapshot.cacheCreation)} />
                                    <SessionDataRow label="Context" value={formatCompactNumber(usageSnapshot.contextSize)} />
                                </SessionRailCard>
                            ) : null}
                        </ScrollView>
                    )}
                </View>
            </View>

            {/* Back button for landscape phone mode when header is hidden */}
            {
                isLandscape && deviceType === 'phone' && (
                    <Pressable
                        onPress={() => router.back()}
                        style={{
                            position: 'absolute',
                            top: safeArea.top + 8,
                            left: 16,
                            width: 44,
                            height: 44,
                            borderRadius: 22,
                            backgroundColor: `rgba(${theme.dark ? '28, 23, 28' : '255, 255, 255'}, 0.9)`,
                            alignItems: 'center',
                            justifyContent: 'center',
                            ...Platform.select({
                                ios: {
                                    shadowColor: '#000',
                                    shadowOffset: { width: 0, height: 2 },
                                    shadowOpacity: 0.1,
                                    shadowRadius: 4,
                                },
                                android: {
                                    elevation: 2,
                                }
                            }),
                        }}
                        hitSlop={15}
                    >
                        <Ionicons
                            name={Platform.OS === 'ios' ? 'chevron-back' : 'arrow-back'}
                            size={Platform.select({ ios: 28, default: 24 })}
                            color="#000"
                        />
                    </Pressable>
                )
            }
        </>
    )
}

function SessionStatusBadge(props: {
    color: string;
    text: string;
}) {
    return (
        <View style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: 8,
            paddingHorizontal: 10,
            paddingVertical: 8,
            borderRadius: 999,
            backgroundColor: `${props.color}18`,
        }}>
            <View style={{
                width: 8,
                height: 8,
                borderRadius: 999,
                backgroundColor: props.color,
            }} />
            <Text style={{
                color: props.color,
                fontSize: 12,
                fontWeight: '700',
            }}>
                {props.text}
            </Text>
        </View>
    );
}

function SessionInfoPill(props: {
    icon: keyof typeof Ionicons.glyphMap;
    label: string;
}) {
    return (
        <View style={{
            flexDirection: 'row',
            alignItems: 'center',
            gap: 6,
            paddingHorizontal: 11,
            paddingVertical: 8,
            borderRadius: 999,
            backgroundColor: 'rgba(127,127,127,0.12)',
        }}>
            <Ionicons name={props.icon} size={14} color="#7a7a7a" />
            <Text style={{
                color: '#666',
                fontSize: 12,
                fontWeight: '600',
            }}>
                {props.label}
            </Text>
        </View>
    );
}

function SessionActionChip(props: {
    disabled?: boolean;
    icon?: keyof typeof Ionicons.glyphMap;
    label: string;
    onPress: () => void;
    primary?: boolean;
}) {
    return (
        <Pressable
            disabled={props.disabled}
            onPress={props.onPress}
            style={({ pressed }) => ({
                minHeight: 42,
                paddingHorizontal: 14,
                paddingVertical: 10,
                borderRadius: 14,
                flexDirection: 'row',
                alignItems: 'center',
                justifyContent: 'center',
                gap: 8,
                backgroundColor: props.primary ? '#161616' : 'rgba(127,127,127,0.12)',
                opacity: props.disabled ? 0.5 : pressed ? 0.78 : 1,
            })}
        >
            {props.icon ? (
                <Ionicons
                    name={props.icon}
                    size={16}
                    color={props.primary ? '#fff' : '#444'}
                />
            ) : null}
            <Text style={{
                color: props.primary ? '#fff' : '#222',
                fontSize: 13,
                fontWeight: '700',
            }}>
                {props.label}
            </Text>
        </Pressable>
    );
}

function SessionRailCard(props: {
    children: React.ReactNode;
    title: string;
}) {
    return (
        <View style={{
            borderRadius: 18,
            backgroundColor: 'rgba(127,127,127,0.08)',
            padding: 14,
            gap: 12,
        }}>
            <Text style={{
                color: '#202020',
                fontSize: 14,
                fontWeight: '800',
            }}>
                {props.title}
            </Text>
            <View style={{ gap: 10 }}>
                {props.children}
            </View>
        </View>
    );
}

function SessionDataRow(props: {
    label: string;
    mono?: boolean;
    value: string;
}) {
    return (
        <View style={{ gap: 4 }}>
            <Text style={{
                color: '#7a7a7a',
                fontSize: 11,
                fontWeight: '700',
                letterSpacing: 0.4,
                textTransform: 'uppercase',
            }}>
                {props.label}
            </Text>
            <Text style={{
                color: '#202020',
                fontSize: 13,
                lineHeight: 18,
                fontFamily: props.mono ? (Platform.OS === 'ios' ? 'Menlo' : 'monospace') : undefined,
            }}>
                {props.value}
            </Text>
        </View>
    );
}

function formatCompactNumber(value: number): string {
    if (!Number.isFinite(value)) {
        return '0';
    }
    if (value >= 1_000_000) {
        return `${(value / 1_000_000).toFixed(1)}M`;
    }
    if (value >= 1_000) {
        return `${(value / 1_000).toFixed(1)}k`;
    }
    return String(value);
}

function ResumeCommandHint({ command }: { command: string }) {
    const { theme } = useUnistyles();
    const [copied, setCopied] = React.useState(false);
    return (
        <View style={{ paddingHorizontal: 16, paddingTop: 12, paddingBottom: 10, gap: 8 }}>
            <Pressable
                onPress={async () => {
                    await Clipboard.setStringAsync(command);
                    setCopied(true);
                    setTimeout(() => setCopied(false), 2000);
                }}
                style={{
                    minHeight: 48,
                    borderRadius: 14,
                    backgroundColor: theme.colors.surfaceHigh,
                    alignItems: 'center',
                    justifyContent: 'center',
                    flexDirection: 'row',
                    gap: 8,
                    paddingHorizontal: 16,
                }}
            >
                <Ionicons name="terminal-outline" size={16} color={theme.colors.textSecondary} />
                <Text style={{
                    color: theme.colors.text,
                    fontSize: 13,
                    fontFamily: Platform.OS === 'ios' ? 'Menlo' : 'monospace',
                    flex: 1,
                }} numberOfLines={1}>
                    {command}
                </Text>
                <Ionicons
                    name={copied ? 'checkmark' : 'copy-outline'}
                    size={16}
                    color={copied ? '#30D158' : theme.colors.textSecondary}
                />
            </Pressable>
            <Text style={{
                color: theme.colors.textSecondary,
                fontSize: 12,
                lineHeight: 16,
                textAlign: 'center',
                paddingHorizontal: 8,
            }}>
                Run this command in your terminal to resume this session
            </Text>
        </View>
    );
}

function CenteredInputWidth(props: {
    children: React.ReactNode;
    horizontalPadding: number;
}) {
    return (
        <View style={{
            width: '100%',
            paddingHorizontal: props.horizontalPadding,
            alignItems: 'center',
        }}>
            <View style={{
                width: '100%',
                maxWidth: layout.maxWidth,
            }}>
                {props.children}
            </View>
        </View>
    );
}
