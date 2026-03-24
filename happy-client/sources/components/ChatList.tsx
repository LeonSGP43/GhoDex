import * as React from 'react';
import { useSession, useSessionMessages } from "@/sync/storage";
import { ActivityIndicator, FlatList, Platform, View } from 'react-native';
import { useCallback } from 'react';
import { useHeaderHeight } from '@/utils/responsive';
import { useSafeAreaInsets } from 'react-native-safe-area-context';
import { MessageView } from './MessageView';
import { Metadata, Session } from '@/sync/storageTypes';
import { ChatFooter } from './ChatFooter';
import { Message } from '@/sync/typesMessage';

export const ChatList = React.memo((props: {
    session: Session;
    topInset?: number;
    bottomInset?: number;
}) => {
    const { messages } = useSessionMessages(props.session.id);
    return (
        <ChatListInternal
            bottomInset={props.bottomInset}
            metadata={props.session.metadata}
            sessionId={props.session.id}
            messages={messages}
            topInset={props.topInset}
        />
    )
});

const ListHeader = React.memo((props: {
    topInset?: number;
}) => {
    const headerHeight = useHeaderHeight();
    const safeArea = useSafeAreaInsets();
    const fallbackInset = headerHeight + safeArea.top + 32;
    return <View style={{ flexDirection: 'row', alignItems: 'center', height: props.topInset ?? fallbackInset }} />;
});

const ListFooter = React.memo((props: {
    bottomInset?: number;
    sessionId: string;
}) => {
    const session = useSession(props.sessionId)!;
    return (
        <View style={{ paddingBottom: props.bottomInset ?? 18 }}>
            <ChatFooter controlledByUser={session.agentState?.controlledByUser || false} />
        </View>
    )
});

const ChatListInternal = React.memo((props: {
    bottomInset?: number,
    metadata: Metadata | null,
    sessionId: string,
    messages: Message[],
    topInset?: number,
}) => {
    const keyExtractor = useCallback((item: any) => item.id, []);
    const renderItem = useCallback(({ item }: { item: any }) => (
        <MessageView message={item} metadata={props.metadata} sessionId={props.sessionId} />
    ), [props.metadata, props.sessionId]);
    return (
        <FlatList
            data={props.messages}
            inverted={true}
            keyExtractor={keyExtractor}
            maintainVisibleContentPosition={{
                minIndexForVisible: 0,
                autoscrollToTopThreshold: 10,
            }}
            contentContainerStyle={{ paddingHorizontal: 4 }}
            keyboardShouldPersistTaps="handled"
            keyboardDismissMode={Platform.OS === 'ios' ? 'interactive' : 'none'}
            renderItem={renderItem}
            ListHeaderComponent={<ListFooter bottomInset={props.bottomInset} sessionId={props.sessionId} />}
            ListFooterComponent={<ListHeader topInset={props.topInset} />}
        />
    )
});
