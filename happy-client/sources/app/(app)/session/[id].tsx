import * as React from 'react';
import { Redirect, useLocalSearchParams } from 'expo-router';
import { SessionView } from '@/-session/SessionView';


export default React.memo(() => {
    const { id } = useLocalSearchParams<{ id?: string }>();
    const sessionId = typeof id === 'string' ? id : '';

    if (!sessionId) {
        return <Redirect href="/" />;
    }

    return (<SessionView id={sessionId} />);
});
