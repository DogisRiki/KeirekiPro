-- ポートフォリオの技術スタックは任意項目のためNULLを許容する
ALTER TABLE portfolios
    ALTER COLUMN tech_stack DROP NOT NULL;
