import { Footer } from "@/components/ui";
import { env } from "@/config/env";
import { Box, Container, Divider, Paper, Typography } from "@mui/material";

/**
 * プライバシーポリシー
 */
export const Privacy = () => {
    return (
        <>
            <Container maxWidth="md" sx={{ py: 6 }}>
                <Paper elevation={3} sx={{ p: 4 }}>
                    <Box>
                        <Typography variant="h4" gutterBottom>
                            プライバシーポリシー
                        </Typography>
                        <Typography variant="body2" color="textSecondary" gutterBottom>
                            最終更新日: 2025年1月7日
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第1条（収集する情報）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本サービスは、ユーザーが入力した職務経歴書のデータを一時的に保存します。このデータは、ユーザーが編集・保存・出力するためのみに使用されます。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第2条（収集しない情報）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本サービスでは、以下の情報を収集しません：
                            <br />
                            1. 個人を特定できる情報（氏名、住所、電話番号など）。
                            <br />
                            2. ユーザーの端末情報、IPアドレス、クッキー情報。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第3条（データの保存期間）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            ユーザーが作成したデータは、公開期間終了後（1か月）に削除されます。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第4条（第三者提供）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            収集した情報は、いかなる第三者にも提供しません。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第5条（データの安全管理）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本サービスでは、収集したデータを適切に管理し、不正アクセスや漏洩が発生しないよう努めます。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第6条（プライバシーポリシーの変更）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本ポリシーは予告なく変更される場合があります。変更後も本サービスを利用される場合、変更後のポリシーに同意したものとみなします。
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
