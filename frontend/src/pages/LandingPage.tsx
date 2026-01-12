import { Link } from "@/components/ui";
import { env } from "@/config/env";
import { paths } from "@/config/paths";
import AccountBoxIcon from "@mui/icons-material/AccountBox";
import BackupIcon from "@mui/icons-material/Backup";
import CardMembershipIcon from "@mui/icons-material/CardMembership";
import CloudDownloadIcon from "@mui/icons-material/CloudDownload";
import CodeIcon from "@mui/icons-material/Code";
import ContentCopyIcon from "@mui/icons-material/ContentCopy";
import FolderSpecialIcon from "@mui/icons-material/FolderSpecial";
import LinkIcon from "@mui/icons-material/Link";
import SearchIcon from "@mui/icons-material/Search";
import SecurityIcon from "@mui/icons-material/Security";
import StarIcon from "@mui/icons-material/Star";
import WorkIcon from "@mui/icons-material/Work";
import { alpha, Box, Button, Container, Paper, Typography, useTheme } from "@mui/material";
import Grid from "@mui/material/Grid2";
import { useNavigate } from "react-router";

/**
 * ランディングページ
 */
export const LandingPage = () => {
    const theme = useTheme();
    const navigate = useNavigate();

    const features = [
        {
            icon: <CodeIcon sx={{ fontSize: 40 }} />,
            title: "エンジニア特化",
            description:
                "プロジェクトごとにフロントエンド、バックエンド、インフラ、開発ツールなど60種類以上の技術スタックを詳細に記録できます。",
        },
        {
            icon: <CloudDownloadIcon sx={{ fontSize: 40 }} />,
            title: "PDF / Markdown出力",
            description:
                "WordやExcelと異なり、特定のソフトウェアやOSに依存しない形式でエクスポート。どの環境でも同じレイアウトで閲覧できます。",
        },
        {
            icon: <BackupIcon sx={{ fontSize: 40 }} />,
            title: "バックアップ & リストア",
            description:
                "JSON形式でデータをバックアップ。いつでもリストアして復元できるので、大切な経歴データを安全に保管できます。",
        },
        {
            icon: <ContentCopyIcon sx={{ fontSize: 40 }} />,
            title: "職務経歴書の複製",
            description: "既存の職務経歴書をコピーして新規作成。応募先に合わせたカスタマイズが簡単に行えます。",
        },
        {
            icon: <SearchIcon sx={{ fontSize: 40 }} />,
            title: "検索 & ソート",
            description:
                "職務経歴書の検索やソート機能で、複数の経歴書を効率的に管理。必要な書類にすぐアクセスできます。",
        },
        {
            icon: <SecurityIcon sx={{ fontSize: 40 }} />,
            title: "セキュアな認証",
            description:
                "メール認証に加え、GoogleアカウントやGitHubアカウントでのログインに対応。2段階認証も設定可能です。",
        },
    ];

    const sections = [
        {
            icon: <WorkIcon />,
            title: "職歴",
            description: "在籍企業と期間を管理",
        },
        {
            icon: <FolderSpecialIcon />,
            title: "プロジェクト",
            description: "担当案件の詳細と技術スタック",
        },
        {
            icon: <CardMembershipIcon />,
            title: "資格",
            description: "保有資格と取得日",
        },
        {
            icon: <AccountBoxIcon />,
            title: "ポートフォリオ",
            description: "個人開発やOSS活動",
        },
        {
            icon: <LinkIcon />,
            title: "SNS",
            description: "GitHub、Qiitaなどのリンク",
        },
        {
            icon: <StarIcon />,
            title: "自己PR",
            description: "強みや実績のアピール",
        },
    ];

    const techStackCategories = [
        {
            category: "Frontend",
            items: [
                "言語",
                "フレームワーク",
                "ライブラリ",
                "ビルドツール",
                "パッケージマネージャー",
                "リンター",
                "フォーマッター",
                "テストツール",
            ],
        },
        {
            category: "Backend",
            items: [
                "言語",
                "フレームワーク",
                "ライブラリ",
                "ビルドツール",
                "パッケージマネージャー",
                "リンター",
                "フォーマッター",
                "テストツール",
                "ORM",
                "認証／認可",
            ],
        },
        {
            category: "Infrastructure",
            items: ["クラウド", "OS", "コンテナ", "データベース", "Webサーバー", "CI/CD", "IaC", "監視", "ログ"],
        },
        {
            category: "Tools",
            items: [
                "ソース管理",
                "プロジェクト管理",
                "コミュニケーション",
                "ドキュメント",
                "API開発",
                "デザイン",
                "エディタ",
                "開発環境",
            ],
        },
    ];

    return (
        <Box
            sx={{
                minHeight: "100vh",
                background: `linear-gradient(135deg, ${alpha(theme.palette.primary.dark, 0.95)} 0%, ${alpha(theme.palette.primary.main, 0.85)} 50%, ${alpha(theme.palette.secondary.dark, 0.9)} 100%)`,
            }}
        >
            {/* Hero Section */}
            <Box
                sx={{
                    pt: { xs: 8, md: 12 },
                    pb: { xs: 6, md: 10 },
                    textAlign: "center",
                    position: "relative",
                    overflow: "hidden",
                    "&::before": {
                        content: '""',
                        position: "absolute",
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        background:
                            "radial-gradient(circle at 20% 80%, rgba(255,255,255,0.1) 0%, transparent 50%), radial-gradient(circle at 80% 20%, rgba(255,255,255,0.08) 0%, transparent 40%)",
                        pointerEvents: "none",
                    },
                }}
            >
                <Container maxWidth="lg">
                    <Typography
                        variant="h1"
                        sx={{
                            fontSize: { xs: "2.5rem", md: "4rem" },
                            fontWeight: 800,
                            color: "#fff",
                            mb: 2,
                            textShadow: "0 4px 20px rgba(0,0,0,0.3)",
                            letterSpacing: "-0.02em",
                        }}
                    >
                        {env.APP_NAME}
                    </Typography>
                    <Typography
                        variant="h2"
                        sx={{
                            fontSize: { xs: "1.1rem", md: "1.5rem" },
                            fontWeight: 400,
                            color: alpha("#fff", 0.9),
                            mb: 4,
                            maxWidth: 700,
                            mx: "auto",
                            lineHeight: 1.8,
                        }}
                    >
                        エンジニアのための職務経歴書作成サービス
                        <br />
                        プロジェクトごとの技術スタックを詳細に記録
                    </Typography>
                    <Box
                        sx={{
                            display: "flex",
                            gap: 2,
                            justifyContent: "center",
                            flexWrap: "wrap",
                        }}
                    >
                        <Button
                            variant="contained"
                            size="large"
                            onClick={() => navigate(paths.register)}
                            sx={{
                                bgcolor: "#fff",
                                color: theme.palette.primary.main,
                                px: 5,
                                py: 1.5,
                                fontSize: "1.1rem",
                                fontWeight: 700,
                                borderRadius: 3,
                                boxShadow: "0 8px 30px rgba(0,0,0,0.2)",
                                "&:hover": {
                                    bgcolor: alpha("#fff", 0.95),
                                    transform: "translateY(-2px)",
                                    boxShadow: "0 12px 40px rgba(0,0,0,0.25)",
                                },
                                transition: "all 0.3s ease",
                            }}
                        >
                            無料で始める
                        </Button>
                        <Button
                            variant="outlined"
                            size="large"
                            onClick={() => navigate(paths.login)}
                            sx={{
                                borderColor: alpha("#fff", 0.6),
                                color: "#fff",
                                px: 5,
                                py: 1.5,
                                fontSize: "1.1rem",
                                fontWeight: 600,
                                borderRadius: 3,
                                borderWidth: 2,
                                "&:hover": {
                                    borderColor: "#fff",
                                    bgcolor: alpha("#fff", 0.1),
                                    borderWidth: 2,
                                },
                                transition: "all 0.3s ease",
                            }}
                        >
                            ログイン
                        </Button>
                    </Box>
                </Container>
            </Box>

            {/* Features Section */}
            <Box sx={{ py: { xs: 6, md: 10 }, bgcolor: "#fff" }}>
                <Container maxWidth="lg">
                    <Typography
                        variant="h3"
                        sx={{
                            fontSize: { xs: "1.8rem", md: "2.5rem" },
                            fontWeight: 700,
                            textAlign: "center",
                            mb: 2,
                            color: theme.palette.text.primary,
                        }}
                    >
                        主な機能
                    </Typography>
                    <Typography
                        variant="body1"
                        sx={{
                            textAlign: "center",
                            mb: 6,
                            color: theme.palette.text.secondary,
                            fontSize: "1.1rem",
                        }}
                    >
                        エンジニアの転職活動を強力にサポート
                    </Typography>
                    <Grid container spacing={4}>
                        {features.map((feature, index) => (
                            <Grid size={{ xs: 12, sm: 6, md: 4 }} key={index}>
                                <Paper
                                    elevation={0}
                                    sx={{
                                        p: 4,
                                        height: "100%",
                                        borderRadius: 4,
                                        border: `1px solid ${alpha(theme.palette.primary.main, 0.1)}`,
                                        transition: "all 0.3s ease",
                                        "&:hover": {
                                            transform: "translateY(-8px)",
                                            boxShadow: `0 20px 40px ${alpha(theme.palette.primary.main, 0.15)}`,
                                            borderColor: theme.palette.primary.main,
                                        },
                                    }}
                                >
                                    <Box
                                        sx={{
                                            color: theme.palette.primary.main,
                                            mb: 2,
                                        }}
                                    >
                                        {feature.icon}
                                    </Box>
                                    <Typography
                                        variant="h6"
                                        sx={{
                                            fontWeight: 700,
                                            mb: 1.5,
                                            color: theme.palette.text.primary,
                                        }}
                                    >
                                        {feature.title}
                                    </Typography>
                                    <Typography
                                        variant="body2"
                                        sx={{
                                            color: theme.palette.text.secondary,
                                            lineHeight: 1.8,
                                        }}
                                    >
                                        {feature.description}
                                    </Typography>
                                </Paper>
                            </Grid>
                        ))}
                    </Grid>
                </Container>
            </Box>

            {/* Sections Overview */}
            <Box
                sx={{
                    py: { xs: 6, md: 10 },
                    bgcolor: alpha(theme.palette.grey[100], 0.5),
                }}
            >
                <Container maxWidth="lg">
                    <Typography
                        variant="h3"
                        sx={{
                            fontSize: { xs: "1.8rem", md: "2.5rem" },
                            fontWeight: 700,
                            textAlign: "center",
                            mb: 2,
                            color: theme.palette.text.primary,
                        }}
                    >
                        充実のセクション構成
                    </Typography>
                    <Typography
                        variant="body1"
                        sx={{
                            textAlign: "center",
                            mb: 6,
                            color: theme.palette.text.secondary,
                            fontSize: "1.1rem",
                        }}
                    >
                        キャリアのすべてを体系的に整理
                    </Typography>
                    <Grid container spacing={3} justifyContent="center">
                        {sections.map((section, index) => (
                            <Grid size={{ xs: 6, sm: 4, md: 2 }} key={index}>
                                <Paper
                                    elevation={0}
                                    sx={{
                                        p: 3,
                                        textAlign: "center",
                                        borderRadius: 3,
                                        bgcolor: "#fff",
                                        border: `1px solid ${alpha(theme.palette.divider, 0.5)}`,
                                        transition: "all 0.3s ease",
                                        "&:hover": {
                                            bgcolor: theme.palette.primary.main,
                                            "& .MuiTypography-root": {
                                                color: "#fff",
                                            },
                                            "& .MuiSvgIcon-root": {
                                                color: "#fff",
                                            },
                                        },
                                    }}
                                >
                                    <Box
                                        sx={{
                                            color: theme.palette.primary.main,
                                            mb: 1,
                                        }}
                                    >
                                        {section.icon}
                                    </Box>
                                    <Typography
                                        variant="subtitle1"
                                        sx={{
                                            fontWeight: 700,
                                            mb: 0.5,
                                            color: theme.palette.text.primary,
                                            transition: "color 0.3s ease",
                                        }}
                                    >
                                        {section.title}
                                    </Typography>
                                    <Typography
                                        variant="caption"
                                        sx={{
                                            color: theme.palette.text.secondary,
                                            transition: "color 0.3s ease",
                                        }}
                                    >
                                        {section.description}
                                    </Typography>
                                </Paper>
                            </Grid>
                        ))}
                    </Grid>
                </Container>
            </Box>

            {/* Tech Stack Section */}
            <Box sx={{ py: { xs: 6, md: 10 }, bgcolor: "#fff" }}>
                <Container maxWidth="lg">
                    <Typography
                        variant="h3"
                        sx={{
                            fontSize: { xs: "1.8rem", md: "2.5rem" },
                            fontWeight: 700,
                            textAlign: "center",
                            mb: 2,
                            color: theme.palette.text.primary,
                        }}
                    >
                        詳細な技術スタック入力
                    </Typography>
                    <Typography
                        variant="body1"
                        sx={{
                            textAlign: "center",
                            mb: 6,
                            color: theme.palette.text.secondary,
                            fontSize: "1.1rem",
                            maxWidth: 700,
                            mx: "auto",
                        }}
                    >
                        プロジェクトごとに使用した技術を4カテゴリ・60項目以上から選択
                        <br />
                        あなたのスキルセットを正確に伝えることができます
                    </Typography>
                    <Grid container spacing={3}>
                        {techStackCategories.map((category, index) => (
                            <Grid size={{ xs: 12, sm: 6, md: 3 }} key={index}>
                                <Paper
                                    elevation={0}
                                    sx={{
                                        p: 3,
                                        height: "100%",
                                        borderRadius: 3,
                                        bgcolor: alpha(theme.palette.primary.main, 0.03),
                                        border: `1px solid ${alpha(theme.palette.primary.main, 0.1)}`,
                                    }}
                                >
                                    <Typography
                                        variant="h6"
                                        sx={{
                                            fontWeight: 700,
                                            mb: 2,
                                            color: theme.palette.primary.main,
                                            fontSize: "1rem",
                                        }}
                                    >
                                        {category.category}
                                    </Typography>
                                    <Box
                                        sx={{
                                            display: "flex",
                                            flexWrap: "wrap",
                                            gap: 1,
                                        }}
                                    >
                                        {category.items.map((item, idx) => (
                                            <Box
                                                key={idx}
                                                sx={{
                                                    px: 1.5,
                                                    py: 0.5,
                                                    bgcolor: "#fff",
                                                    borderRadius: 2,
                                                    fontSize: "0.8rem",
                                                    color: theme.palette.text.secondary,
                                                    border: `1px solid ${alpha(theme.palette.divider, 0.5)}`,
                                                }}
                                            >
                                                {item}
                                            </Box>
                                        ))}
                                    </Box>
                                </Paper>
                            </Grid>
                        ))}
                    </Grid>
                </Container>
            </Box>

            {/* CTA Section */}
            <Box
                sx={{
                    py: { xs: 8, md: 12 },
                    background: `linear-gradient(135deg, ${theme.palette.primary.main} 0%, ${theme.palette.primary.dark} 100%)`,
                    textAlign: "center",
                    position: "relative",
                    overflow: "hidden",
                    "&::before": {
                        content: '""',
                        position: "absolute",
                        top: 0,
                        left: 0,
                        right: 0,
                        bottom: 0,
                        background: "radial-gradient(circle at 30% 70%, rgba(255,255,255,0.1) 0%, transparent 50%)",
                        pointerEvents: "none",
                    },
                }}
            >
                <Container maxWidth="md">
                    <Typography
                        variant="h3"
                        sx={{
                            fontSize: { xs: "1.8rem", md: "2.5rem" },
                            fontWeight: 700,
                            color: "#fff",
                            mb: 2,
                        }}
                    >
                        今すぐ始めましょう
                    </Typography>
                    <Typography
                        variant="body1"
                        sx={{
                            color: alpha("#fff", 0.9),
                            mb: 4,
                            fontSize: "1.1rem",
                        }}
                    >
                        無料で利用できます。あなたのキャリアを最高の形でアピールしましょう。
                    </Typography>
                    <Button
                        variant="contained"
                        size="large"
                        onClick={() => navigate(paths.register)}
                        sx={{
                            bgcolor: "#fff",
                            color: theme.palette.primary.main,
                            px: 6,
                            py: 1.5,
                            fontSize: "1.1rem",
                            fontWeight: 700,
                            borderRadius: 3,
                            boxShadow: "0 8px 30px rgba(0,0,0,0.2)",
                            "&:hover": {
                                bgcolor: alpha("#fff", 0.95),
                                transform: "translateY(-2px)",
                                boxShadow: "0 12px 40px rgba(0,0,0,0.25)",
                            },
                            transition: "all 0.3s ease",
                        }}
                    >
                        無料で新規登録
                    </Button>
                </Container>
            </Box>

            {/* Footer */}
            <Box
                sx={{
                    py: 4,
                    bgcolor: theme.palette.grey[900],
                    textAlign: "center",
                }}
            >
                <Container maxWidth="lg">
                    <Box
                        sx={{
                            display: "flex",
                            justifyContent: "center",
                            gap: 4,
                            mb: 2,
                            flexWrap: "wrap",
                        }}
                    >
                        <Link
                            to={paths.terms}
                            target="_blank"
                            rel="noopener noreferrer"
                            sx={{
                                color: alpha("#fff", 0.7),
                                textDecoration: "none",
                                fontSize: "0.9rem",
                                "&:hover": {
                                    color: "#fff",
                                },
                            }}
                        >
                            利用規約
                        </Link>
                        <Link
                            to={paths.privacy}
                            target="_blank"
                            rel="noopener noreferrer"
                            sx={{
                                color: alpha("#fff", 0.7),
                                textDecoration: "none",
                                fontSize: "0.9rem",
                                "&:hover": {
                                    color: "#fff",
                                },
                            }}
                        >
                            プライバシーポリシー
                        </Link>
                    </Box>
                    <Typography variant="body2" sx={{ color: alpha("#fff", 0.5) }}>
                        © {new Date().getFullYear()} {env.APP_NAME}. All rights reserved.
                    </Typography>
                </Container>
            </Box>
        </Box>
    );
};
