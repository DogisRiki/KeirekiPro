-- プロジェクトの概要・役割とポートフォリオの概要は1000文字まで入力できるため、255文字の上限を外してTEXTにする
ALTER TABLE projects
    ALTER COLUMN overview TYPE TEXT,
    ALTER COLUMN role TYPE TEXT;

ALTER TABLE portfolios
    ALTER COLUMN overview TYPE TEXT;
