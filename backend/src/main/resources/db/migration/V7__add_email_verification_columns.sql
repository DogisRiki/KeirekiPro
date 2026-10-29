-- メールアドレスの持ち主の確認の状態を持つ列を足す。今ある行は email_verified_at が NULL になり、確認前として扱われる
ALTER TABLE users ADD COLUMN email_verified_at TIMESTAMP NULL;
ALTER TABLE users ADD COLUMN pending_email VARCHAR(255) NULL;
