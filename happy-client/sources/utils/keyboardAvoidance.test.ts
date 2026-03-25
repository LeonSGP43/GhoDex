import { describe, expect, it } from 'vitest';
import { resolveAndroidKeyboardInset } from './keyboardAvoidance';

describe('resolveAndroidKeyboardInset', () => {
    it('returns zero when keyboard is hidden', () => {
        expect(resolveAndroidKeyboardInset({
            height: 640,
            isVisible: false,
            safeAreaBottom: 24,
        })).toBe(0);
    });

    it('subtracts the bottom safe area from visible keyboard height', () => {
        expect(resolveAndroidKeyboardInset({
            height: 816,
            isVisible: true,
            safeAreaBottom: 48,
        })).toBe(768);
    });

    it('clamps negative inset to zero', () => {
        expect(resolveAndroidKeyboardInset({
            height: 16,
            isVisible: true,
            safeAreaBottom: 32,
        })).toBe(0);
    });
});
