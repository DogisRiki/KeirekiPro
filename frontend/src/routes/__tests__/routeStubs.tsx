import { Outlet } from "react-router";

/**
 * 差し替えた画面を描画中に失敗させるかどうか
 */
export const stubState = { throwInPage: false };

/**
 * 画面の代わりに、画面名だけを表示する部品を作る
 */
export const createStubPage = (name: string) => {
    const StubPage = () => {
        if (stubState.throwInPage) {
            throw new Error(`${name} failed`);
        }
        return <div>page:{name}</div>;
    };
    return StubPage;
};

/**
 * レイアウトの代わりに、どのレイアウトの下かが分かる部品を作る
 */
export const createStubLayout = (name: string) => {
    const StubLayout = () => (
        <div data-testid={`layout:${name}`}>
            <Outlet />
        </div>
    );
    return StubLayout;
};
