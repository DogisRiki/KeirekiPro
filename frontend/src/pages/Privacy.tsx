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
                        <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
                            プライバシーポリシー
                        </Typography>
                        <Typography variant="body2" color="textSecondary" gutterBottom>
                            最終更新日: 2026年1月12日
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第1条（はじめに）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            {`本プライバシーポリシーは、${env.APP_NAME}（以下「本サービス」）における個人情報の取扱いについて定めるものです。本サービスを利用される方（以下「ユーザー」）は、本ポリシーに同意の上、本サービスをご利用ください。`}
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第2条（収集する情報）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本サービスでは、以下の情報を収集します。
                        </Typography>
                        <Typography component="p" gutterBottom sx={{ mt: 2 }}>
                            <strong>2.1 アカウント情報</strong>
                            <br />
                            （1）メールアドレス
                            <br />
                            （2）パスワード（暗号化して保存）
                            <br />
                            （3）表示名（任意）
                        </Typography>
                        <Typography component="p" gutterBottom sx={{ mt: 2 }}>
                            <strong>2.2 外部認証サービス利用時の情報</strong>
                            <br />
                            Google または GitHub アカウントでログインする場合、以下の情報を当該サービスから取得します。
                            <br />
                            （1）メールアドレス
                            <br />
                            （2）表示名
                            <br />
                            （3）外部サービスのユーザー識別子
                        </Typography>
                        <Typography component="p" gutterBottom sx={{ mt: 2 }}>
                            <strong>2.3 職務経歴書データ</strong>
                            <br />
                            ユーザーが入力する職務経歴書の内容（氏名、職歴、プロジェクト経験、資格、ポートフォリオ、SNSリンク、自己PRを含む）を保存します。
                        </Typography>
                        <Typography component="p" gutterBottom sx={{ mt: 2 }}>
                            <strong>2.4 ログ情報</strong>
                            <br />
                            セキュリティおよび障害調査の目的で、以下の情報をログとして記録します。
                            <br />
                            （1）IPアドレス
                            <br />
                            （2）アクセス日時
                            <br />
                            （3）リクエストURL
                            <br />
                            （4）ユーザーエージェント（ブラウザ情報）
                            <br />
                            （5）HTTPステータスコード
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第3条（情報の利用目的）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            収集した情報は、以下の目的で利用します。
                            <br />
                            1. 本サービスの提供・運営
                            <br />
                            2. ユーザー認証およびアカウント管理
                            <br />
                            3. 二段階認証コードの送信
                            <br />
                            4. パスワードリセットの案内
                            <br />
                            5. サービスに関する重要なお知らせの送信（登録完了通知、退会完了通知、サービス終了通知等）
                            <br />
                            6. 不正アクセスの検知およびセキュリティの確保
                            <br />
                            7. システム障害時の調査および対応
                            <br />
                            8. 本サービスの改善および新機能の開発
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第4条（外部サービスの利用）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本サービスでは、以下の外部サービスを利用しています。
                        </Typography>
                        <Typography component="p" gutterBottom sx={{ mt: 2 }}>
                            <strong>4.1 Google Analytics</strong>
                            <br />
                            本サービスでは、利用状況を把握するためにGoogle Analyticsを使用しています。Google
                            Analyticsは、Cookieを使用してユーザーの利用情報（アクセス元の国・地域、使用デバイス、ブラウザ情報等）を収集しますが、個人を特定する情報は収集しません。Google
                            Analyticsの利用規約およびプライバシーポリシーについては、Google社のウェブサイトをご確認ください。
                        </Typography>
                        <Typography component="p" gutterBottom sx={{ mt: 2 }}>
                            <strong>4.2 認証サービス</strong>
                            <br />
                            Google および GitHub
                            のOAuth認証を利用しています。これらのサービスを通じた認証を選択した場合、各サービスのプライバシーポリシーが適用されます。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第5条（Cookieの使用）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本サービスでは、以下の目的でCookieを使用しています。
                            <br />
                            1. ユーザー認証状態の維持（セッション管理）
                            <br />
                            2. セキュリティ対策（CSRF対策）
                            <br />
                            3. Google Analyticsによる利用状況の分析
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第6条（情報の保存期間）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1. アカウント情報および職務経歴書データ：アカウント削除時まで保存します。
                            <br />
                            2. ログ情報：本サービス終了時まで保存します。
                            <br />
                            3. ユーザーは、本サービス上でいつでも自身のアカウントおよびデータを削除することができます。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第7条（第三者提供）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            開発者は、以下の場合を除き、ユーザーの個人情報を第三者に提供しません。
                            <br />
                            1. ユーザーの同意がある場合
                            <br />
                            2. 法令に基づく場合
                            <br />
                            3.
                            人の生命、身体または財産の保護のために必要がある場合であって、ユーザーの同意を得ることが困難であるとき
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第8条（データの安全管理）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            開発者は、収集した情報の漏洩、滅失、毀損の防止その他の安全管理のために、以下の措置を講じています。
                            <br />
                            1. 通信の暗号化（HTTPS）
                            <br />
                            2. パスワードのハッシュ化
                            <br />
                            3. アクセス制御の実施
                            <br />
                            4. 定期的なセキュリティ対策の見直し
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第9条（ユーザーの権利）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            ユーザーは、以下の権利を有します。
                            <br />
                            1. 自身の個人情報の開示を請求する権利
                            <br />
                            2. 自身の個人情報の訂正または削除を請求する権利
                            <br />
                            3. 自身のアカウントをいつでも削除する権利
                            <br />
                            これらの権利の行使については、下記のお問い合わせ先までご連絡ください。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第10条（プライバシーポリシーの変更）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1.
                            本ポリシーの内容は、法令その他本ポリシーに別段の定めのある事項を除いて、ユーザーに通知することなく変更することができるものとします。
                            <br />
                            2. 変更後のプライバシーポリシーは、本サービス上に掲載したときから効力を生じるものとします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第11条（お問い合わせ）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本ポリシーに関するお問い合わせは、以下の連絡先までお願いいたします。
                            <br />
                            {env.APP_EMAIL}
                        </Typography>
                    </Box>
                </Paper>
            </Container>
            <Footer />
        </>
    );
};
