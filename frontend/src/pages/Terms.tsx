import { Footer } from "@/components/ui";
import { env } from "@/config/env";
import { Box, Container, Divider, Paper, Typography } from "@mui/material";

/**
 * 利用規約
 */
export const Terms = () => {
    return (
        <>
            <Container maxWidth="md" sx={{ py: 6 }}>
                <Paper elevation={3} sx={{ p: 4 }}>
                    <Box>
                        <Typography variant="h4" gutterBottom>
                            利用規約
                        </Typography>
                        <Typography variant="body2" color="textSecondary" gutterBottom>
                            最終更新日: 2025年1月7日
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第1条（適用）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            {`この利用規約（以下「本規約」）は、${env.APP_NAME}（以下「本サービス」）に適用されるものとします。本サービスを利用される方（以下「ユーザー」）は、本規約に同意したものとみなします。`}
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第2条（サービス内容）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本サービスは、転職活動をサポートするための職務経歴書作成/管理ツールを提供します。本サービスは1か月間の公開期間を予定しており、無料で提供されます。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第3条（免責事項）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1. 本サービスの利用は、ユーザー自身の責任で行うものとします。
                            <br />
                            2. 本サービスの利用により生じた損害について、開発者は一切の責任を負いません。
                            <br />
                            3. 本サービスの機能や内容は予告なく変更または終了する場合があります。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第4条（禁止事項）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            以下の行為を禁止します：
                            <br />
                            1. 不正アクセス、サービスの改変、その他サービス運営を妨げる行為。
                            <br />
                            2. 他のユーザーまたは第三者に不利益を与える行為。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第5条（プライバシー）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            ユーザーのプライバシー情報の取り扱いについては、プライバシーポリシーをご確認ください。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第6条（規約の変更）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本規約は予告なく変更される場合があります。変更後も本サービスを利用される場合、変更後の規約に同意したものとみなします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第7条（お問い合わせ）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            お問い合わせは以下までご連絡ください：
                            <br />
                            {env.APP_EMAIL}
                        </Typography>
                    </Box>
                </Paper>
            </Container>
            <Footer isFixed={false} />
        </>
    );
};
