import { create } from "zustand";

interface LeaveGuardState {
    /**
     * 画面を離れてよいかを利用者に確かめる関数。離れてよいときに true で解決する。
     * 保存していない変更が無いときは null
     */
    confirmLeave: (() => Promise<boolean>) | null;
    setConfirmLeave: (confirmLeave: (() => Promise<boolean>) | null) => void;
}

/**
 * 画面の移動を伴わずに画面を離れる操作(ログアウトなど)の前に、確かめを出すためのストア
 */
export const useLeaveGuardStore = create<LeaveGuardState>()((set) => ({
    confirmLeave: null,
    setConfirmLeave: (confirmLeave) => set({ confirmLeave }),
}));
