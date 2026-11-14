-- 利用者の操作が読み書きする問い合わせ。
-- 退会の11の問い合わせは、Java 版の UserMapper.xml の削除の問い合わせ(delete)と同じ表を同じ順で消す。
-- 呼ぶ側は、1つのトランザクションの中で、このファイルに並べた順に呼ぶ。
-- 利用者の連携とロールを消す問い合わせは auth.sql にもあるが、退会の順をこのファイルだけで読めるように、ここにも置く。
-- Java 版の削除の問い合わせに表が足されたら、ここにも同じ位置に足す。

-- name: DeleteAccountProjectTechStacks :exec
DELETE FROM project_tech_stacks
WHERE project_id IN (
    SELECT p.id
    FROM projects p
        INNER JOIN resumes r ON r.id = p.resume_id
    WHERE r.user_id = $1
);

-- name: DeleteAccountProjects :exec
DELETE FROM projects
WHERE resume_id IN (SELECT id FROM resumes WHERE user_id = $1);

-- name: DeleteAccountCareers :exec
DELETE FROM careers
WHERE resume_id IN (SELECT id FROM resumes WHERE user_id = $1);

-- name: DeleteAccountCertifications :exec
DELETE FROM certifications
WHERE resume_id IN (SELECT id FROM resumes WHERE user_id = $1);

-- name: DeleteAccountPortfolios :exec
DELETE FROM portfolios
WHERE resume_id IN (SELECT id FROM resumes WHERE user_id = $1);

-- name: DeleteAccountSnsPlatforms :exec
DELETE FROM sns_platforms
WHERE resume_id IN (SELECT id FROM resumes WHERE user_id = $1);

-- name: DeleteAccountSelfPromotions :exec
DELETE FROM self_promotions
WHERE resume_id IN (SELECT id FROM resumes WHERE user_id = $1);

-- name: DeleteAccountResumes :exec
DELETE FROM resumes WHERE user_id = $1;

-- name: DeleteAccountAuthProviders :exec
DELETE FROM user_auth_providers WHERE user_id = $1;

-- name: DeleteAccountRoles :exec
DELETE FROM user_roles WHERE user_id = $1;

-- name: DeleteAccountUser :exec
DELETE FROM users WHERE id = $1;
