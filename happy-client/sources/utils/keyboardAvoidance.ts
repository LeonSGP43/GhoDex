export interface AndroidKeyboardInsetInput {
    height: number;
    isVisible: boolean;
    safeAreaBottom: number;
}

export function resolveAndroidKeyboardInset(input: AndroidKeyboardInsetInput): number {
    if (!input.isVisible) {
        return 0;
    }

    if (!Number.isFinite(input.height) || input.height <= 0) {
        return 0;
    }

    const safeAreaBottom = Number.isFinite(input.safeAreaBottom) ? input.safeAreaBottom : 0;
    return Math.max(0, Math.round(input.height - safeAreaBottom));
}
