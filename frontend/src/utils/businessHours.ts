/** 日本時間の UTC からのずれ(ミリ秒) */
const JST_OFFSET_MS = 9 * 60 * 60 * 1000;

/** 営業時間の始まり(日本時間 8:00。この時刻を含む)を、0:00 からの分で表したもの */
const OPEN_MINUTES = 8 * 60;

/** 営業時間の終わり(日本時間 20:00。この時刻を含まない)を、0:00 からの分で表したもの */
const CLOSE_MINUTES = 20 * 60;

/**
 * 営業時間かどうかを判定する
 * 日本時間で月曜から金曜の 8:00 以上 20:00 未満を営業時間とする。祝日は平日と同じく扱う。
 * 端末の時刻帯の設定によらず、日本時間で判定する。
 * @param now 判定する時刻
 * @returns 営業時間なら true
 */
export const isBusinessHours = (now: Date): boolean => {
    const jst = new Date(now.getTime() + JST_OFFSET_MS);
    const day = jst.getUTCDay();
    const isWeekday = day >= 1 && day <= 5;
    const minutes = jst.getUTCHours() * 60 + jst.getUTCMinutes();
    return isWeekday && minutes >= OPEN_MINUTES && minutes < CLOSE_MINUTES;
};
