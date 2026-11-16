-- マスタの操作が読む問い合わせ。
-- Java 版の CertificationQueryMapper.xml、SnsPlatformQueryMapper.xml、TechStackQueryMapper.xml と、同じ列を同じ並べ方で読む。

-- 資格の名前を読む。Java 版と同じく、並べ方を指定しない(試作の P1 で、Java 版と同じ並びになることを確かめた)。
-- name: ListCertificationNames :many
SELECT
    name
FROM
    certification_mst;

-- SNS の名前を読む。Java 版と同じく、並べ方を指定しない。
-- name: ListSnsPlatformNames :many
SELECT
    name
FROM
    sns_platform_mst;

-- 技術スタックの名前を、大分類と小分類と組にして読む。呼ぶ側が、大分類と小分類で答えの鍵に振り分ける。
-- name: ListTechStacks :many
SELECT
    c.main_category,
    c.sub_category,
    m.name
FROM
    tech_stack_category_mst c
    JOIN tech_stack_mst m ON m.category_code = c.code
ORDER BY
    c.main_category,
    c.sub_category,
    m.id;
