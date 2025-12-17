import type { AuthProvider } from "@/types";
import { Box, Link, Typography } from "@mui/material";
import { FaGithub } from "react-icons/fa";
import { FcGoogle } from "react-icons/fc";

export interface AuthProviderFieldProps {
    // 連携済みプロバイダー
    connected: AuthProvider[];
    // 連携解除可能フラグ
    canRemoveProvider: boolean;
    // 連携解除ハンドラ
    onRemove: (provider: AuthProvider) => void;
}

/**
 * 外部連携アイコン表示
 */
export const AuthProviderField = ({ connected, canRemoveProvider, onRemove }: AuthProviderFieldProps) => {
    const providerIcon: Record<AuthProvider, JSX.Element> = {
        google: <FcGoogle size={24} />,
        github: <FaGithub size={22} />,
    };

    return (
        <Box sx={{ display: "flex", flexDirection: "column", gap: 1.5 }}>
            {(Object.keys(providerIcon) as AuthProvider[]).map((p) => {
                const isConnected = connected.includes(p);
                return (
                    <Box
                        key={p}
                        sx={{
                            display: "flex",
                            alignItems: "center",
                            gap: 1,
                            opacity: isConnected ? 1 : 0.4,
                        }}
                    >
                        {/* アイコン */}
                        {providerIcon[p]}

                        {/* ステータス表示 */}
                        <Typography sx={{ flex: 1, fontSize: 14 }}>
                            {isConnected ? (
                                <>
                                    連携されています
                                    {canRemoveProvider && (
                                        <>
                                            {" "}
                                            (
                                            <Link
                                                component="button"
                                                underline="hover"
                                                type="button"
                                                onClick={() => onRemove(p)}
                                            >
                                                解除する
                                            </Link>
                                            )
                                        </>
                                    )}
                                </>
                            ) : (
                                "未連携"
                            )}
                        </Typography>
                    </Box>
                );
            })}
        </Box>
    );
};
