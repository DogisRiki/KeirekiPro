/**
 * CodeQL の診断を確かめる見本の PR のためのファイル。マージしない。
 */
export const showCodeqlSample = (): void => {
    document.body.innerHTML = window.location.hash.slice(1);
};
