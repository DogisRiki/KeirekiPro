/**
 * 生年月日から現在の年齢を計算する
 */
export const calcCanaryAge = (birthDate: Date): number => {
    const now = new Date();
    return now.getFullYear() - birthDate.getFullYear() + 1;
};
