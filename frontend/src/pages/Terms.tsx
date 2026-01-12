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
                        <Typography variant="h4" gutterBottom sx={{ fontWeight: 600 }}>
                            利用規約
                        </Typography>
                        <Typography variant="body2" color="textSecondary" gutterBottom>
                            最終更新日: 2026年1月12日
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第1条（適用）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            {`この利用規約（以下「本規約」）は、${env.APP_NAME}（以下「本サービス」）の利用条件を定めるものです。本サービスを利用するすべての方（以下「ユーザー」）は、本規約に同意したものとみなします。`}
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第2条（サービス内容）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1. 本サービスは、エンジニア向けの職務経歴書作成・管理ツールを無料で提供します。
                            <br />
                            2.
                            本サービスは個人が開発・運営するポートフォリオプロジェクトであり、商用サービスではありません。
                            <br />
                            3.
                            本サービスは予告なく終了する場合があります。サービス終了時には、事前に登録されたメールアドレス宛に通知いたします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第3条（アカウント）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1. ユーザーは、本サービスを利用するためにアカウントを作成する必要があります。
                            <br />
                            2. ユーザーは、自己の責任においてアカウント情報を管理するものとします。
                            <br />
                            3.
                            ユーザーは、アカウント情報を第三者に利用させ、または貸与、譲渡、売買等をしてはなりません。
                            <br />
                            4.
                            アカウント情報の管理不十分、使用上の過誤、第三者の使用等による損害の責任はユーザーが負うものとします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第4条（禁止事項）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            ユーザーは、本サービスの利用にあたり、以下の行為をしてはなりません。
                            <br />
                            1. 法令または公序良俗に違反する行為
                            <br />
                            2. 犯罪行為に関連する行為
                            <br />
                            3. 本サービスのサーバーまたはネットワークの機能を破壊したり、妨害したりする行為
                            <br />
                            4. 本サービスの運営を妨害するおそれのある行為
                            <br />
                            5. 他のユーザーに関する個人情報等を収集または蓄積する行為
                            <br />
                            6. 不正アクセスをし、またはこれを試みる行為
                            <br />
                            7. 他のユーザーに成りすます行為
                            <br />
                            8. 本サービスに関連して、反社会的勢力に対して直接または間接に利益を供与する行為
                            <br />
                            9. その他、開発者が不適切と判断する行為
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第5条（本サービスの提供の停止等）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1.
                            開発者は、以下のいずれかの事由があると判断した場合、ユーザーに事前に通知することなく本サービスの全部または一部の提供を停止または中断することができるものとします。
                            <br />
                            （1）本サービスにかかるシステムの保守点検または更新を行う場合
                            <br />
                            （2）地震、落雷、火災、停電または天災などの不可抗力により、本サービスの提供が困難となった場合
                            <br />
                            （3）システムまたは通信回線等が事故により停止した場合
                            <br />
                            （4）その他、開発者が本サービスの提供が困難と判断した場合
                            <br />
                            2.
                            開発者は、本サービスの提供の停止または中断により、ユーザーまたは第三者が被ったいかなる不利益または損害についても、一切の責任を負わないものとします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第6条（免責事項）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1.
                            開発者は、本サービスに事実上または法律上の瑕疵（安全性、信頼性、正確性、完全性、有効性、特定の目的への適合性、セキュリティなどに関する欠陥、エラーやバグ、権利侵害などを含みます）がないことを明示的にも黙示的にも保証しておりません。
                            <br />
                            2.
                            開発者は、本サービスに起因してユーザーに生じたあらゆる損害について、一切の責任を負いません。
                            <br />
                            3.
                            開発者は、本サービスに関して、ユーザーと他のユーザーまたは第三者との間において生じた取引、連絡または紛争等について一切責任を負いません。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第7条（サービス内容の変更等）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            開発者は、ユーザーへの事前の告知をもって、本サービスの内容を変更、追加または廃止することがあり、ユーザーはこれを承諾するものとします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第8条（利用規約の変更）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1.
                            開発者は、必要と判断した場合には、ユーザーの個別の同意を要せず、本規約を変更することができるものとします。
                            <br />
                            2.
                            本規約の変更後、本サービスの利用を継続したユーザーは、変更後の規約に同意したものとみなします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第9条（個人情報の取扱い）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本サービスの利用によって取得する個人情報については、別途定める「プライバシーポリシー」に従い適切に取り扱うものとします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第10条（準拠法・裁判管轄）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            1. 本規約の解釈にあたっては、日本法を準拠法とします。
                            <br />
                            2.
                            本サービスに関して紛争が生じた場合には、東京地方裁判所を第一審の専属的合意管轄裁判所とします。
                        </Typography>
                    </Box>
                    <Divider sx={{ my: 3 }} />
                    <Box>
                        <Typography variant="h6" gutterBottom>
                            第11条（お問い合わせ）
                        </Typography>
                        <Typography component="p" gutterBottom>
                            本規約に関するお問い合わせは、以下の連絡先までお願いいたします。
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
