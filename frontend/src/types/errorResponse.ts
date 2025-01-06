/**
 * バリデーションエラーレスポンス
 * @example
 * {
 *   "message": "入力内容に誤りがあります",
 *   "errors": {
 *     "email": [
 *       "メールアドレスの形式が無効です"
 *     ],
 *     "password": [
 *       "パスワードは8文字以上で入力してください",
 *       "パスワードは英数字を含める必要があります"
 *     ],
 *     "name": [
 *       "氏名は必須項目です"
 *     ]
 *   }
 * }
 */
export interface ErrorResponse {
    message: string;
    errors: {
        [field: string]: string[];
    };
}
