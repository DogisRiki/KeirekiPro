# 調べたこと

## 今あるものについて確かめた文

- requirements.md はじめに「今の Go 版は、出力の操作の要求に、未実装であることを示す答えを返す」: backend/internal/httpapi/unimplemented.go 152-160行
- requirements.md はじめに「要求を送る側は、要求の Accept のヘッダで、PDF か Markdown かを選ぶ」: backend/src/main/java/com/example/keirekipro/presentation/resume/controller/ExportResumeController.java 45行、54-64行
- requirements.md はじめに「Java 版は、PDF を既定のフォントと文字の大きさと表の見出しの色で作り、ファイルを保存させる答えを返す」: ExportResumeController.java 69行、74-75行。backend/src/main/java/com/example/keirekipro/usecase/resume/ExportResumeUseCase.java 95-98行
- requirements.md はじめに「画面は、利用者が経歴書を Markdown で保存するときに、この操作を使う。画面は、この操作で PDF を求める要求を送らない」: frontend/src/features/resume/components/resume-list/ResumeCardMenu.tsx 113-126行。frontend/src/features/resume/components/resume/BottomMenu.tsx 81行、91行(PDF の保存はプレビューを開く。設定を付けない出力は `format: "markdown"` だけで呼ぶ)
- requirements.md 要件1の受入基準1「API の仕様書は、設定を付けない出力が、Accept に `application/pdf` を含む要求に既定の設定の PDF を返すと書いている」: backend/api/openapi.yaml 788-790行
- requirements.md 要件1の受入基準1「画面は、4つの文字の大きさを 0.5 刻みに直し、表の見出しの色を小文字の6桁の16進数で送る」と、要件3の受入基準1「画面は、この5種類の断る条件に当たる要求を送らない」: frontend/src/features/resume/utils/pdfPreview.ts 3行、21-33行、77-92行。frontend/src/features/resume/components/export/ResumePdfPreviewModal.tsx 109-146行
- requirements.md 要件3の受入基準4「Java 版と同じく、設定を付けた出力の要求の本文を受入基準1の断る条件で確かめてから、経歴書があるかと、経歴書の持ち主と、出力の前提を確かめる」: backend/src/main/java/com/example/keirekipro/presentation/resume/controller/ExportResumeWithSettingsController.java 50-56行(本文の検査が、経歴書を読む前に走る)
- requirements.md はじめに「出し方は、ファイルを画面に表示させる「inline」と、ファイルを保存させる「attachment」の2つである」: backend/src/main/java/com/example/keirekipro/presentation/resume/dto/ExportResumeRequest.java 36-37行。backend/src/main/java/com/example/keirekipro/presentation/resume/controller/ExportResumeWithSettingsController.java 68-71行
- requirements.md はじめに「画面は、PDF のプレビューを見せるときと、プレビューで選んだ設定で PDF を保存するときに、この操作を使う」: frontend/src/features/resume/hooks/useResumePdfPreview.ts 59-63行、76-83行
- requirements.md はじめに「出力の前提は、経歴書の名前、日付、姓、名と、職歴、プロジェクト、自己PR のそれぞれ1件以上の項目である」: backend/src/main/java/com/example/keirekipro/domain/service/resume/ResumeExportRuleCheckService.java 28-56行
- requirements.md 範囲「API の仕様書には、出力の操作も書かれている」: backend/internal/httpapi/unimplemented.go 153行、158行(生成した型 gen.ExportResumeRequestObject と gen.ExportResumeWithSettingsRequestObject)
- requirements.md 範囲「HTML から A4 の PDF を作る Go 版の部品。この部品は、起動したまま持つ Chromium で PDF を作る」: backend/internal/platform/pdf/pdf.go 1行、46行、158-160行
- requirements.md 範囲「PDF を比べる部品。この部品は、頁の数、フォント、文字の大きさ、表の色、頁ごとの文字、文字の位置を比べる」: backend/compat/pdfcmp/pdfcmp.go 33-37行。.kiro/specs/backend-go-replacement/design.md 668-676行
- requirements.md 範囲「比べる経歴書のデータ」の5種類: backend/compat/fixtures/resumes/empty.sql 1行、many-pages.sql 1行、long-text.sql 1行、fonts.sql 1-2行、fonts-NotoSansJP.json と fonts-NotoSerifJP.json の全体、sizes-NotoSansJP.json と sizes-NotoSerifJP.json の全体
- requirements.md 範囲「認証のまとまりと、マスタと経歴書のまとまりの Go 版は、main に入っている」: .kiro/specs/backend-go-replacement/progress.md 37-39行
- requirements.md 範囲「頁の数と改頁の位置は同じになり、文字の位置は1〜2pt ずれた」: .kiro/specs/backend-go-replacement/research.md 115-123行
- requirements.md 範囲「出力のまとまりの比べる検査で初めて確かめると書いている」: .kiro/specs/backend-go-replacement/research.md 316行
- requirements.md 範囲「次の4つを Go で試しに作らなかった。Markdown の本文とファイル名のヘッダは、Java 版の動きだけを確かめた」: .kiro/specs/backend-go-replacement/research.md 46行、50-52行、132-150行
- requirements.md 範囲「変えた動きの一覧には、出力に関わる次の3つの違い」: backend/compat/changed-behaviors.yaml 19行(名前の並び)、56-61行(入力の足りない経歴書の出力)、65-70行(PDF の文字の位置と「〜」)
- requirements.md 要件1の受入基準1「画面が送る要求は、次の4種類である」: frontend/src/features/resume/api/exportResume.ts 44-45行、56行、80行。frontend/src/features/resume/hooks/useResumePdfPreview.ts 63行、78行
- requirements.md 要件1「画面は、保存するファイルの名前を、答えの Content-Disposition のヘッダから取る」: frontend/src/features/resume/hooks/useResumePdfPreview.ts 83行
- requirements.md 要件1の受入基準2「経歴書の ID の場所に ID の形でない文字を入れた要求」(Java 版は無い経歴書と同じ答えを返す): backend/src/main/java/com/example/keirekipro/usecase/resume/ResumeIdResolver.java 25-27行
- requirements.md 要件2の受入基準1「既定の設定は、フォントが Noto Sans JP、タイトルの文字の大きさが 16、日付が 10、氏名が 10、見出しが 11.5、表の見出しの色が `#d9d9d9` である」: backend/src/main/java/com/example/keirekipro/usecase/resume/export/ResumePdfExportSettings.java 24-31行
- requirements.md 要件2の受入基準2「`<` `>` `&` `"` `'` の文字を、Java 版と同じ形に書き換えて Markdown に出す」: .kiro/specs/backend-go-replacement/research.md 134行
- requirements.md 要件2の受入基準3「ファイル名を、Java 版と同じ規則で、経歴書の名前から作る」: ExportResumeUseCase.java 87-91行。backend/src/main/java/com/example/keirekipro/shared/utils/FileUtil.java 81-90行。.kiro/specs/backend-go-replacement/research.md 138-148行
- requirements.md 要件3の受入基準1の5種類の断る条件: ExportResumeRequest.java 32-37行、46行、82-91行、103-120行、132行、141行、165-179行
- requirements.md 要件3の受入基準2「「入力エラーがあるため、PDFプレビューを表示できません。」で、それ以外のときは「職務経歴書をエクスポートできません。」で始まり」: ExportResumeUseCase.java 72-77行。状態の番号 400 は backend/src/main/java/com/example/keirekipro/presentation/shared/AppExceptionHandler.java 161-165行
- requirements.md 要件3の受入基準3「状態の番号 404 と「対象の職務経歴書データが存在しません。」」: ExportResumeUseCase.java 63-64行。AppExceptionHandler.java 112-113行
- requirements.md 要件4の受入基準1「Java 版が無い経歴書の要求に返す答えと同じ答え」と、足りないものの一覧より先に持ち主を確かめること: ExportResumeUseCase.java 66-72行
- requirements.md 要件5の受入基準2「検査は、状態の番号と、Content-Type と Content-Disposition のヘッダと、答えの本文を比べる」: backend/compat/harness/compare.go 111-117行、199行、304行
- requirements.md 要件5の受入基準4「その設計は、PDF の出力と Markdown の出力を測る操作に含めた」と、同時に2件のメモリの最大: .kiro/specs/backend-go-replacement/design.md 649-651行
- requirements.md 要件6の受入基準1「出力の操作は経歴書を書き換えない」(Java 版): ExportResumeUseCase.java 59行(読み取りだけのトランザクション)
- requirements.md 要件7の受入基準1「Java 版は、4つの文字の大きさを 0.5 刻みに丸め、表の見出しの色を小文字の16進数の形に直してから PDF を作る」: ResumePdfExportSettings.java 61-76行、81-85行
- requirements.md 要件7の受入基準3「置き換えの spec の進み具合の表の、出力のまとまりの行」: .kiro/specs/backend-go-replacement/progress.md 32行、41行
- requirements.md 要件1の受入基準2「画面は、どの要求でも、Accept のヘッダに `application/json` を付けて送る」: frontend/src/features/resume/api/exportResume.ts 56行、80行。Accept に `application/json` が無い要求に Java 版が 401 と空の本文を返すことは、backend/compat/changed-behaviors.yaml 56-63行と .kiro/specs/backend-go-replacement/research.md 172行
- 試作の記録「Thymeleaf の TEXT の形の繰り返しは、本文が空白と改行で始まり、改行と空白で終わるときだけ、繰り返しの間の空白と改行を落とす」: Thymeleaf 3.1.5 の sources jar の org/thymeleaf/engine/IteratedGatheringModelProcessable.java 551-700行
- 試作の記録「Java 版の Markdown のひな形の繰り返し」: backend/src/main/resources/templates/resume/markdown/default.md 14行、21行、25行、43行、191行、201行、218行、227行
- 試作の記録「Go 版の PDF の部品は、用紙を A4 にし、CSS のページの大きさを優先し、背景を印刷する」: backend/internal/platform/pdf/pdf.go 227-231行
- 試作の記録「PDF を比べる部品の許す幅と、頁ごとの文字の直し方」: backend/compat/pdfcmp/pdfcmp.go 31-38行、264-279行、386行
- 試作の記録「比べる仕組みは、ページの大きさの違いを許さない」: .kiro/specs/backend-go-replacement/design.md 655-702行
- 試作の記録「同じでなければならないものと、例外の「〜」」: .kiro/specs/backend-go-replacement/requirements.md 236-243行
- requirements.md 要件2の受入基準4の3つの違い(ページの大きさ、PDF から写した字、長い文の折り返しの数値): この research.md の「試作の記録」の「PDF で Java 版と同じにできなかったこと」(Java 版と Go 版の PDF を試作で作って測った)
- requirements.md 要件5の受入基準5「置き換えの spec の設計が決めた比べ方は、ページの大きさの違いを許さず、写した字をそのまま比べ、語と行の区切りで字を組にし、ページの画像の、同じ色の画素がつながった広がりを箱として、表の見出しと罫線の色を取る」: backend/compat/pdfcmp/pdfcmp.go 31-38行、246-248行、264-282行、386-410行、473-477行、548行。.kiro/specs/backend-go-replacement/design.md 655-702行
- design.md「受け口は、マスタと経歴書の26の操作を持つ ResumeService を通して、internal/resume の Service を呼ぶ」: backend/internal/httpapi/resumes.go 17-51行、53行。backend/internal/resume/service.go 28-31行
- design.md「経歴書の受け口は、ログインした利用者の ID を context から取り、答えを authResponse で書く」: backend/internal/httpapi/resumes.go 62行、84-96行。backend/internal/httpapi/resumeresponses.go 12-30行、227-250行
- design.md「本文を JSON のまま受ける操作は、仕様書の本文の型に x-go-type: json.RawMessage を付けている。ExportResumeRequest には付いていない」: backend/api/openapi.yaml 1819行、1830行、1844行、2036-2051行。backend/internal/httpapi/resumes.go 75-80行
- design.md「authResponse は、状態の番号、Set-Cookie、Location、Content-Type、本文を持ち、Content-Disposition の欄を持たない」: backend/internal/httpapi/authresponses.go 15-24行、117-136行
- design.md「Accept の行を context に入れる中間処理は、Google と GitHub のログインの開始と戻り先の操作のときだけ働く」: backend/internal/httpapi/auth.go 286-310行。backend/internal/httpapi/server.go 209行
- design.md「本文を JSON として読めない要求は 400、未実装は 501、ほかの誤りは 500 で答える」: backend/internal/httpapi/server.go 210-222行
- design.md「Options の ResumeHandlers と resumeOperations は、26の操作を受け持つ」: backend/internal/httpapi/server.go 49-51行、93-95行
- design.md「応答の型の数を確かめるテストは、26を確かめる」: backend/internal/httpapi/resumes_test.go 803-836行
- design.md「Unimplemented は、出力の2つの操作に未実装の誤りを返す」: backend/internal/httpapi/unimplemented.go 152-160行
- design.md「main.go は、経歴書の Service を、PDF の部品を作る前に作る」: backend/cmd/keirekipro/main.go 70-71行、95行、173-179行、186-197行
- design.md「PDF の部品の Render は、HTML の文字列を受けて PDF のバイトを返す。同時に作る数は2、打ち切りは30秒」: backend/internal/platform/pdf/pdf.go 24-29行、158-160行、227-231行
- design.md「Service の部品の束は、Pool と Now を持つ」: backend/internal/resume/service.go 18-25行、34-40行
- design.md「経歴書を読む処理は、ID を読めないとき、無いとき、ほかの利用者の経歴書のときに、同じ 404 の誤りを返す」: backend/internal/resume/service.go 64-77行。backend/internal/resume/errors.go 18-20行、131-140行
- design.md「読めない本文の誤りと、業務の決まりの誤りと、入力欄の誤りの作り方」: backend/internal/resume/errors.go 142-151行。backend/internal/auth/exported.go 100-107行
- design.md「Java 版のフォントの名前の直し方と、文字の大きさの丸め方と、色の直し方」: backend/src/main/java/com/example/keirekipro/usecase/resume/export/ResumePdfExportSettings.java 55-94行
- design.md「Java 版のひな形は、Markdown の default.md と、PDF の simple.html の2つである」: backend/src/main/resources/templates/resume/markdown/default.md、backend/src/main/resources/templates/resume/pdf/simple.html
- design.md「Go 版の本番のイメージは、Java 版と同じ4つのフォントのファイルを置く」: docker/backend-go/Dockerfile.prod 40-58行
- design.md「開発環境と CI は、poppler-utils を入れている。pdftohtml は poppler-utils に入っている」: docker/backend-go/Dockerfile 7行、14-19行。.github/workflows/ci.yaml 505-509行
- design.md「CI は、比べる検査と、版をまたぐ確認を、backend-compat の仕事で動かす」: .github/workflows/ci.yaml 481行、512-516行。backend/Makefile 127-136行
- design.md「golang.org/x/text は、すでに直接の依存である」: backend/go.mod 36行。backend/internal/resume/order.go(import)
- design.md「筋書きの要求は json と multipart と body_file を持ち、版に送る段では body_file と content_type を書けない」: backend/compat/harness/scenario.go 154-200行、369-387行
- design.md「比べる検査は、Content-Type と Content-Disposition のヘッダを値のまま比べ、本文を Content-Type で選んだ比べ方で比べる」: backend/compat/harness/compare.go 77行、106-114行、117行、188-208行
- design.md「JSON の本文の比べ方は、オブジェクトを鍵ごとに比べ、鍵の順によらない。配列は長さと順で比べる」: backend/compat/harness/compare.go 257-300行
- design.md「PDF を比べる部品は、Describe を比べる検査に渡す」: backend/compat/pdfcmp/pdfcmp.go 31-38行、83行、113行。backend/compat/harness/compareenv.go 69行
- design.md「版をまたぐ筋書きを読み、向きごとに段の版を確かめるテスト」: backend/compat/harness/cross_test.go 57-61行、175-180行、263行。backend/compat/cross_test.go 264-310行
- design.md「時間を測る筋書きの形」: backend/compat/scenarios/resumes/perf-get-resume.yaml の全体
- design.md「退会した利用者の筋書きの形」: backend/compat/scenarios/resumes/deleted-user.yaml 1-40行
- design.md「比べるデータに、2つのフォントと文字の大きさの要求の本文がある」: backend/compat/fixtures/resumes/ の fonts-NotoSansJP.json、fonts-NotoSerifJP.json、sizes-NotoSansJP.json、sizes-NotoSerifJP.json
- design.md「変えた動きの一覧の最後は CB-055 で、match を書かずに単体テストで確かめる書き方がある」: backend/compat/changed-behaviors.yaml 715-729行(CB-054、CB-055)
- design.md「進み具合の表の出力の行は、未定と未着手である」: .kiro/specs/backend-go-replacement/progress.md 41行
- design.md「設定を付けた出力で形式を markdown にした要求に、Java 版は、Accept が `application/pdf, application/json` でも `text/markdown, application/json` でも、Markdown と、本文の出し方の Content-Disposition で答える」: この research.md の「試作の記録」の「Accept と形式の組の答え」(試作で Java 版に送った)
- design.md「Java 版の、本文の欄の型と違う値の読み方」: この research.md の「試作の記録」の「本文の数の欄と型の読み方」(試作で Java 版に送った)
- design.md「Java 版の GET は、Accept の行に application/pdf の字の並びがあれば PDF、無くて text/markdown があれば Markdown、どちらも無ければ 406 にする」: ExportResumeController.java 54-64行
- design.md「Java 版の POST は、出し方が inline なら inline、それ以外なら attachment の Content-Disposition を、UTF-8 のファイル名で作る」: ExportResumeWithSettingsController.java 57-84行
- design.md「Java 版は、ID を読み、経歴書を探し、持ち主を確かめ、出力の前提を確かめてから、形式で PDF か Markdown を作り、名前からファイル名を作る」: ExportResumeUseCase.java 59-91行
- design.md「Java 版は、PDF の設定が無ければ既定の設定を使い、設定の値を直せないときは 400 の業務の誤りにする」: ExportResumeUseCase.java 95-112行
- design.md「出力の前提の文言は8つで、名前、日付、氏名、姓、名、職歴、プロジェクト、自己PR の順に確かめる」: ResumeExportRuleCheckService.java 25-58行
- design.md「本文の欄の注釈と文言。errors の鍵は Java の欄の名前と、isPdfSettingsRequired と isSpecifiedOnce の名前で決まる」: ExportResumeRequest.java 32-47行、80-92行、101-121行、130-142行、163-181行
- design.md「Rは255以下で入力してください は句点が無い」: ExportResumeRequest.java 167行
- design.md「ファイル名は、空白だけなら resume にし、前後の空白を除き、\ / : * ? " < > | を _ に、制御の字を消し、_ だけなら resume にし、255 字で切る」: FileUtil.java 81-90行
- design.md「既定の設定と、フォントの名前の直し方と、文字の大きさの丸め方と、色の直し方」: ResumePdfExportSettings.java 24-94行
- design.md「Java 版の出力のモデルとひな形を組み立てるクラス」: backend/src/main/java/com/example/keirekipro/infrastructure/export/resume/ResumeExportModelBuilder.java、ThymeleafResumeMarkdownExporter.java、ThymeleafResumePdfExporter.java
- design.md「ResumeService は26のメソッドを持ち、resume.Service がそれを満たすことをコンパイルで確かめる」: backend/internal/httpapi/resumes.go 17-51行、53行
- design.md「Options の ResumeHandlers のコメントと resumeOperations は26の操作を書く。fallback は生成したインタフェースを埋め込む」: backend/internal/httpapi/server.go 49-51行、93-174行、176-179行
- design.md「New は ResumeHandlers があれば経歴書の受け口を使い、strict の中間処理は authRequestMiddleware と updateUserInfoMiddleware の2つである」: backend/internal/httpapi/server.go 183-204行、208行
- design.md「authRequestMiddleware は StartOidcAuthorization と HandleOidcCallback のときだけ、host と Accept の行を context に入れる」: backend/internal/httpapi/auth.go 296-304行
- design.md「経歴書の答えの型のコメントは26の操作を書き、Visit の関数が並ぶ」: backend/internal/httpapi/resumeresponses.go 12-14行、227行
- design.md「authResponse の欄と、authJSON と authText と write」: backend/internal/httpapi/authresponses.go 15-24行、43-51行、118-136行
- design.md「生成した GET の要求の型は経歴書の ID だけを持ち、Accept を持たない。生成した Markdown の答えは charset を付けない」: backend/internal/httpapi/gen/api.gen.go 5836-5838行、5844行、5878-5880行
- design.md「生成した POST の要求の型は、本文を ExportResumeRequest の型で持つ」: backend/internal/httpapi/gen/api.gen.go 315行、388行、1190行、5971-5975行
- design.md「x-go-type: json.RawMessage で受ける前例」: backend/internal/httpapi/gen/api.gen.go 397行
- design.md「仕様書の出力の2つの操作と、POST の説明の errors の項目名」: backend/api/openapi.yaml 781-866行、2036行
- design.md「main.go は newPDF で PDF の部品を作り、resume.New を PDF の部品より前に呼ぶ」: backend/cmd/keirekipro/main.go 71行、95行、173行、175-179行、186-197行
- design.md「入口のテストの前例 TestRun_PassesResumeHandlers と、harness が本物の pdf.New を使うこと」: backend/cmd/keirekipro/main_test.go 307行、942行
- design.md「筋書きの要求と期待の欄。body_file と content_type は絶対の URL の段だけで書ける」: backend/compat/harness/scenario.go 153-170行、189-200行、366-387行
- design.md「measure_memory の欄」: backend/compat/harness/scenario.go 48-50行
- design.md「LoadScenarios は scenarios の下のすべての .yaml を読む」: backend/compat/harness/scenario.go 249行、254行
- design.md「JSON の本文は expandJSON のあとに json.Marshal で作り、application/json で送る」: backend/compat/harness/capture.go 247-272行
- design.md「版に送る段の期待は CheckExpect と session.CheckValues で確かめ、絶対の URL の段は checkAbsoluteExpect で content_type も確かめる」: backend/compat/harness/steps.go 135-137行、142行。backend/compat/harness/send.go 254-279行
- design.md「比べるヘッダは Content-Type、Content-Disposition、Cache-Control、Location。本文は application/pdf を PDF の比べ方、text/ を字の比べ方で比べる」: backend/compat/harness/compare.go 117行、188-208行
- design.md「まとまりを完了と記す状態と、足りない操作を求める関数」: backend/compat/harness/coverage.go 17行、110行。backend/compat/compat_test.go 64行
- design.md「出力のまとまりの番号は 4」: backend/compat/harness/operations.go 21行、30行、121-122行
- design.md「時間を測る筋書きを読むテストの前例と、メモリの最大を PDF の出力の筋書きだけで測るという文」: backend/compat/harness/perfmeasure_test.go 388行、429行、451行
- design.md「変えた動きの一覧の項目の数を確かめるテストは 55 を期待する」: backend/compat/harness/match_test.go 328行
- design.md「CB-003 と CB-004 は group 4 で、match を書かない」: backend/compat/changed-behaviors.yaml 56-71行
- design.md「比べる検査と、版をまたぐ確認と、時間を測る検査の Makefile の入口」: backend/Makefile 126-136行
- design.md「進み具合の表の、認証、利用者、マスタと経歴書の行は比べる検査に通った」: .kiro/specs/backend-go-replacement/progress.md 36-40行
- design.md「PDF を比べる部品の許す幅、違いの種類、Describe と Compare の形」: backend/compat/pdfcmp/pdfcmp.go 31-49行、83行、113行
- design.md「PDF を比べる部品は pdfinfo、pdffonts、pdftotext の -layout と -bbox-layout、pdftoppm を呼ぶ」: backend/compat/pdfcmp/pdfcmp.go 202行、226行、248行、282行、348行
- design.md「PDF を比べる部品のテスト」: backend/compat/pdfcmp/pdfcmp_test.go 36行、55行、81行、106行、126行、149行。backend/compat/pdfcmp/pdf_helper_test.go
- design.md「比べる検査は PDF の比べ方に pdfcmp.Describe を使う」: backend/compat/harness/compareenv.go 69行
- design.md「fixtures/resumes と scenarios/resumes にあるファイル」: backend/compat/fixtures/resumes/ と backend/compat/scenarios/resumes/ の一覧
- design.md「比べる検査は、Go 版を本番のイメージ docker/backend-go/Dockerfile.prod で動かす。本番のイメージは Java 版と同じ4つのフォントのファイルを置く」: backend/compat/harness/images.go 44-45行。docker/backend-go/Dockerfile.prod 51-57行
- design.md「開発環境のイメージは、chromium と fonts-noto-cjk を入れ、Java 版の4つのフォントのファイルを置かない」: docker/backend-go/Dockerfile 9行、15-20行
- design.md「PDF を比べる部品が許す行の高さの違いは 0.35pt である」: backend/compat/pdfcmp/pdfcmp.go 34-35行
- design.md「PDF を比べる部品のテストは、フォントと位置と色を決めた PDF をテストの中で作る。テストは compat の build tag を持つ」: backend/compat/pdfcmp/pdf_helper_test.go 1行、18-29行
- design.md「経歴書 101 と 401 は user1 の経歴書で、user2 は basic.sql にいる」: backend/compat/fixtures/resumes/empty.sql 1-3行。backend/compat/fixtures/resumes/fonts.sql 1行。backend/compat/fixtures/users/basic.sql(user1 と user2 の行)
- design.md「経歴書 201 は自己PR を持たず、301 と 401 は持つ。401 は6つの欄のすべてに項目を持つ。201 の名前は日本語である」: backend/compat/fixtures/resumes/many-pages.sql、long-text.sql、fonts.sql の INSERT の文
- design.md「fonts-NotoSansJP.json は、形式 pdf、出し方 attachment の本文の全体である」: backend/compat/fixtures/resumes/fonts-NotoSansJP.json の全体
- design.md「経歴書 ID の 6xx と 7xx と利用者 ID の 9xx は、fixtures と scenarios のどこでも使っていない」: backend/compat/fixtures と backend/compat/scenarios を grep で探した
- design.md「many-pages.sql は、比べる検査そのもののテストの2つの筋書きが使う」: backend/compat/compat_test.go 96行。backend/compat/cross_test.go 193行
- design.md「退会した利用者の筋書きは、resume-ops.sql の退会用の利用者を使う」: backend/compat/scenarios/resumes/deleted-user.yaml 11行。backend/compat/fixtures/resumes/resume-ops.sql 10-12行
- design.md「Java 版の PDF のひな形は、利用者が書いた文を th:text で書き、改行を CSS の white-space: pre-line で出す」: backend/src/main/resources/templates/resume/pdf/simple.html 198行、277行、436行
- design.md「httpapi には、multipart の部分の Content-Disposition を読む型と関数を持つ contentdisposition.go がすでにある」: backend/internal/httpapi/contentdisposition.go 14行、43行
- design.md「parseAccept は、Spring と同じく Accept の行を引用符の外の , で分けて読み、読めない型があるときと、型が50を超えるときは ok を false にし、型が無いときは */* とする」: backend/internal/httpapi/auth.go 356-379行
- design.md「Service のメソッドは、利用者の ID を uuid.UUID で、経歴書の ID を経路の文字列で受ける」: backend/internal/resume/service.go 64行
- design.md「PDF を比べる部品の許す幅のコメントは、置き換えの spec の design.md の表を指す」: backend/compat/pdfcmp/pdfcmp.go 30行
- design.md「筋書きの要求は headers で Accept を送れる」: backend/compat/harness/scenario.go 160行。backend/compat/scenarios/auth/oidc-google.yaml 50行
- design.md「版に送る段の本文の欄を確かめる validateVersionBody は、版に送る段の expect の content_type を断る」: backend/compat/harness/scenario.go 367-387行
- design.md「resume-ops.sql の退会用の利用者 340 は、名前と日付と姓と名と、職歴、プロジェクト、自己PR を含む6つの欄の項目を持つ経歴書 350 を持つ」: backend/compat/fixtures/resumes/resume-ops.sql 6-7行、26行、33行、59行、108行、114行
- design.md「main.go は、resume.New を 173行で呼び、PDF の部品を 175行で作る」: backend/cmd/keirekipro/main.go 173-179行
- design.md「比べる検査は、Content-Type と Content-Disposition のヘッダを値のまま比べ、本文を Content-Type で選んだ比べ方(PDF は PDF を比べる部品、text/ は字)で比べる」: backend/compat/harness/compare.go 117行、187-206行
- design.md「版をまたぐ動かし方は、to: other の段で前の段と違う版へ移り、最後の段をその前の版に送る段と違う版に送る」: backend/compat/harness/scenario.go 28-34行。backend/compat/harness/cross.go 36-39行、60-77行
- design.md「TestCrossRoute_ResumeSteps は、2つの向きで、値を確かめる段の送り先がその前の変える段と違うことを確かめる」: backend/compat/harness/cross_test.go 258-293行
- design.md「measure_memory は perf の筋書きにだけ書け、認証の時間を測る筋書きのテストは、メモリの最大を PDF の出力の筋書きだけで測ると確かめる」: backend/compat/harness/scenario.go 48-50行、508-523行。backend/compat/harness/perfmeasure_test.go 429行
- design.md「退会のあと、退会の前の経歴書の取得は、2つの版とも 404 になる」: backend/compat/scenarios/resumes/deleted-user.yaml 6-7行、63行
- design.md「TestCoverage_Operations は、進み具合の表で完了と記したまとまりの操作が、比べる動かし方の筋書きに出てくることを求める。完了とみなす状態は、作り終えた、比べる検査に通った、本番で動いている」: backend/compat/compat_test.go 63-89行。backend/compat/harness/coverage.go 17行
- design.md「進み具合の表の出力の行は、spec が未定で状態が未着手である。応答の時間を比べた結果の表は、まとまりと操作ごとに1行を持つ」: .kiro/specs/backend-go-replacement/progress.md 41行、54-66行
- design.md「`ExportResumeUseCase` は `usecase/resume/` の直下にあり、`usecase/resume/export/` の下には `ResumePdfExportSettings` がある」: backend/src/main/java/com/example/keirekipro/usecase/resume/ExportResumeUseCase.java、usecase/resume/export/ResumePdfExportSettings.java
- design.md「`fonts.sql` は、ポートフォリオと自己PR の項目の名前の頭に `A ` と `B ` を付けて順を決める。CB-001 は、ポートフォリオと SNS と自己PR を並べる規則の違いである」: backend/compat/fixtures/resumes/fonts.sql 56-67行、backend/compat/changed-behaviors.yaml 14-19行

## 試作の記録(要件7の受入基準1)

### 試し方

- Java 版: main の Java 版を組み立て、試作用のコンテナで動かした。試作用の DB(`keireki_proto`)と Redis の DB 7 を使い、所有者の DB と Redis の DB 0 には触れていない。
  要求を送る筋書き(試作の作業場所の `capture.sh`)で、5つの経歴書に、GET の Markdown と PDF、POST の inline と attachment の4種類を送り、答えを保存した。
  経歴書 401 には、フォント2種類、文字の大きさの2種類、変わった値の2種類(`odd-sizes` `odd-sizes2`)、Markdown を選ぶ2種類、断る条件に当たる13種類も送った。
- Go 版: Java 版の `ResumeExportModelBuilder` と Markdown と HTML のひな形を Go に写した試作の命令(`protoexport`)を、`docker/backend-go/Dockerfile.prod` を写したイメージで動かした。
  経歴書は `internal/resume` の今の読み取りで読み、PDF は `internal/platform/pdf` の今の部品で作った。
- 使った経歴書:
  - 101: 比べる検査のデータの empty.sql(出力の前提を満たさない)
  - 201: many-pages.sql に自己PR を1件足したもの(12ページ)
  - 301: long-text.sql(長い文と改行)
  - 401: fonts.sql(フォントと文字の大きさの設定)
  - 601: 試作だけで作った、出力の前提を満たす中で項目が最も少ない経歴書
  - 701: 試作だけで作った、名前と本文に `< > & " '` と `\` `:` と日本語を入れた経歴書
- 試作のコードとデータは、リポジトリに入れていない。

### 結果

| 試したこと | 結果 |
|---|---|
| Markdown の本文 | 7件すべてが1バイトも違わなかった。Thymeleaf が繰り返しの間の改行を落とす動きは、Go のひな形で、2回目以降の繰り返しの先頭の改行を出さない書き方にして写した。1行の形の繰り返し(職歴、資格、SNS)は落とさない |
| `< > & " '` の書き換え | 701 の Markdown は Java 版と1バイトも違わなかった。`&amp;` `&lt;` `&gt;` `&quot;` `&#39;` に書き換える |
| Content-Disposition のヘッダ | 28件すべてが Java 版と同じだった。701 の名前の日本語と記号も同じだった |
| PDF の設定の値の直し方 | 16.24、10.3、9.79、12.75、文字列の "10.5"、6、72、11.2999、rgb の形、大文字の16進数で、タイトル、日付、氏名の文字の大きさと、見出しの箱の高さが Java 版と同じだった(例: odd-sizes2 は 6.466、77.598、11.316、11.855) |
| メモリの最大 | 201 と 301 の PDF を同時に作る組を5回続けたとき、コンテナのメモリの最大は 406,839,296 バイト(約388MiB)だった。置き換えの spec の上限の 1792MB に収まる |
| 1件の時間(Go 版) | 601 は約45ms、201 は約130-145ms、401 は約60-70ms。Java 版は測っていない |
| PDF の見た目 | 下の「PDF で Java 版と同じにできなかったこと」のとおり |

### PDF で Java 版と同じにできなかったこと

- **ページの大きさ**: Java 版は 595.275×841.875pt、Go 版は 594.96×841.92pt だった。Chromium は CSS の `size` にどの値を書いても 0.96pt 刻みの大きさにするので、一致させる値が無い。
  `@page` を書かずに用紙の指定だけにすると 595.92×842.88pt になり、もっと離れる。違いは横 0.3pt、縦 0.05pt で、目では分からない
- **PDF から写した字**: Java 版の PDF から写すと、「年」「理」「利」「立」「行」「見」「流」「量」「車」「離」「料」「識」「切」「度」「葉」「落」「例」「力」「鈴」「郎」「冷」「良」などが、見た目の同じ別の字(CJK 互換漢字、U+F9xx と U+FAxx)になり、「-」は U+2011 になる。
  Go 版の PDF からは普通の字が写る。互換漢字を普通の字に直し(NFC)、U+2011 を「-」に直すと、頁ごとの字は一致した。写した字で検索すると見つからないのは Java 版の側である
- **長い文の折り返し**: Chromium の字の幅は、36字で 0.24pt 狭い(Java 版 273.0pt、Go 版 272.758pt)。そのため、長い文で、1行に入る字が1字多くなる行があった(301 の1ページの57行目)。試したデータでは、改頁の位置は変わらなかった

### CSS で Java 版と同じにしたこと

- **表の見出しの繰り返し**: Chromium は、表の見出しを `display: table-header-group` のままにすると、改頁した先のページでも繰り返す。Java 版は繰り返さない。職務内容の表の見出しを `display: table-row-group` にすると、Java 版と同じになった
- **職務内容の表の列の幅**: Java 版の列の線の位置は 31.25、96.5、396.75、563.75pt だった。Go 版で列の幅を 12.5%、56.5%、31% にすると 98.25pt と 399.0pt になり、ずれた。
  期間の列を 87px、業務内容の列を 400.33px、技術の列を自動にすると、0.25pt 以内でそろった
- **2頁目から先の上の余白**: Java 版の2頁目から先の中身は、強制の改頁でも自然な改頁でも、Go 版より 5.9pt 下にあった(1行目の上の端が Java 版 30.8pt、Go 版 24.9pt)。
  `@page { size: A4; margin: calc(9mm + 5.9pt) 11mm 9mm 11mm; }` と `@page :first { margin-top: 9mm; }` を書くと、30.9pt と 30.8pt になり、頁の数は変わらなかった
- **SNS の項目の間**: Java 版の SNS の項目の間は約 17.2pt、Go 版は約 11.3pt だった。401 の2頁目では、「■SNS」から下が最大 16.7pt ずれた。
  `.sns-item` に `padding-top: 5.9pt` を足すと、SNS の項目と、その下の自己PR の行が 2pt 以内でそろった
- **フォントの上と下の寸法**: 日付の文字の大きさを 72 にした 401-odd-sizes2 で、Java 版の日付の字は Go 版より 2.1pt 上にあった。見出しの文字の大きさを既定と違う値にした 401-sizes-NotoSansJP と 401-sizes-NotoSerifJP でも、見出しの行だけが 2.3pt ずれた。
  ずれは文字の大きさに比例し、行の高さを変えなかった(次の行のずれは元に戻った)。行の中で字を置く高さの違いである。
  Go 版のひな形の `@font-face` で、4つのフォントを `local()` で指し、`ascent-override: 112.1%; descent-override: 32.7%` を付けると、日付のずれは 0.6pt に、見出しのずれは 1.6pt 以内になった。
  フォントのファイルの寸法は、Noto Sans JP が上 1160、下 288、Noto Serif JP が上 1151、下 286(1000 を1文字の大きさとする値。hhea の表)なので、上と下の和を変えずに、字を置く高さを 0.039 文字分上げる値である。
  Noto Serif JP に `111.2%` と `32.5%` を付けても、結果は変わらなかった
- **合字**: Chromium は、英字の「fl」と「fi」を1字の合字(U+FB02 と U+FB01)にして描いた(401 の「influence」と「certified」)。Java 版は合字にしない。
  `body` に `font-variant-ligatures: none` を足すと、合字にならなくなり、字の数が Java 版と同じになった。位置は変わらなかった
- 上の4つを直したあとの位置の比べ方の試しは、下の「比べ方の試し」に書く

### 比べ方の試し

- 試した組: PDF の答えの13組(201、301、401 のフォント2種類と文字の大きさ2種類と変わった値2種類と GET と POST の inline と attachment、601、701)
- `pdftotext -raw` の字の並び: 2つの版で字の出る順が違う(「)」の位置が違う)ので、比べ方に使えない
- `pdftotext -layout` の文書の全体の字: 互換漢字を NFC で直し、U+2011 を「-」に、「～」(U+FF5E)を「〜」(U+301C)に直し、空白を除くと、401 のほかの組で一致した。401 では、表の列の字が1行にまとまる順が2つの版で違い、一致しなかった
- `pdftotext -bbox-layout` の行: 行の数は13組すべてで一致した。頁ごとに、字が同じ行どうしを、位置の近い順に組にすると、301 の折り返しの違う10行のほかは、すべての行が組になった。組になった行の位置のずれは、横が最大 0.71pt、縦が最大 1.95pt(401-odd-sizes2 の SNS の行)だった。201(12頁)は縦が最大 0.98pt だった
- 301 の組にならなかった10行は、つないだ字が Java 版と Go 版で同じだった(折り返しの位置だけが違う)
- 列ごとの字の並び: Java 版の行の左の端を、2pt 以内どうしで列にまとめ、2つの版の行を、列、頁、上からの位置の順に並べてつなぐと、13組すべてで字の並びが一致した(401 を含む。201 は 16,000字)
- `pdftohtml -xml -fontfullname` の字ごとのフォントと色: Go 版の「月」を康熙部首の字(U+2F49)で、「・」を U+2027 で、「長」を U+2ED1 で写すので、字そのものを比べる材料には使えない。
  一方、フォントの名前と色の組ごとに字の数を数えると、合字を止めたあとは13組すべてで一致した(例: 401 は NotoSansJP-Bold の黒が 274字、NotoSansJP-Regular の黒が 1,589字)。
  `pdftohtml` は文字の大きさを整数に丸めるので(13 と 14 で揺れる)、文字の大きさは行の高さで比べる
- 頁ごとの色: 頁の画像のうち、白でなく、字の箱の外にある色の集まり(9画素以上)は、13組すべてで一致した(例: `000000` と `d9d9d9`、401 の色を変えた組では `b4c7e7`)。画素の数は罫線の描き方で違った

### PDF を比べる部品が、2つの版の PDF で成り立たなかったこと

- ページの大きさの違いを許さないので、上のとおり一致させられない大きさの違いで、すべての PDF が「違う」になる
- 写した字の比べ方は、互換漢字と U+2011 を直さないので、ほぼすべてのページが「違う」になる
- 語の切れ目を、PDF から字を写す道具(pdftotext の `-bbox-layout`)の語の単位で取るので、2つの版で語の数が違う(例: 188 と 109)。語を順に組にして位置を比べる比べ方が成り立たない
- 行を、同じ道具の `-layout` で取るので、違う列の字が1行にまとまったり、まとまらなかったりする
- 表の色を、ページの画像の同じ色の画素がつながった広がりから取るので、罫線の描き方が違う2つの版で、拾う広がりが違う
- 互換漢字と U+2011 を直し、空白を除いて比べると、頁ごとの字は全件で一致した。改頁の位置は同じだった

### Accept と形式の組の答え

経歴書 401 に、Java 版で送った答えである。

| 要求 | Java 版の答え |
|---|---|
| GET、Accept が `application/json` だけか `*/*` | 406、`{"message":"対応していない形式が指定されました。","errors":{}}` |
| GET、Accept が `application/pdf` だけ | 200、PDF、attachment |
| GET、Accept が `text/markdown` だけ | 200、Markdown、attachment |
| POST、形式が markdown、出し方が attachment、Accept が `application/pdf, application/json` か `text/markdown, application/json` | 200、`text/markdown;charset=utf-8`、attachment |
| POST、形式が markdown、出し方が inline、PDF の設定が無い | 200、`text/markdown;charset=utf-8`、inline |
| POST、形式が pdf、Accept が `application/pdf` だけか `application/json` だけ | 200、PDF、inline |
| POST、断る本文、Accept が `application/pdf` だけ | 401、本文は空(CB の「Accept に application/json が無い要求」) |
| 経歴書の ID の場所に `not-a-uuid` | GET も POST も 404 |

### 本文の数の欄と型の読み方

経歴書 401 に、Accept を `application/pdf, application/json` にした POST で、1つの欄だけを変えた本文を送った答えである。「PDF」は 200 と PDF、「{}」は 400 と「入力エラーがあります。」と空の errors(読めない本文)を指す。

| 欄 | 送った値 | Java 版の答え |
|---|---|---|
| rgb の r | 12.7、255.9、-0.5、-0.9、12.0 | PDF(小数を 0 の向きに切り捨てる) |
| rgb の r | `" 12"`、`"+12"`、`"012"` | PDF |
| rgb の r | `""` | 「Rは入力必須です。」 |
| rgb の r | 256、2147483647、300.5 | 「Rは255以下で入力してください」 |
| rgb の r | -1、-2147483648 | 「Rは0以上で入力してください。」 |
| rgb の r | 1e10、2147483648、`"0x0c"`、`"1e2"`、`[12]`、`{}` | {} |
| rgb | `{"red":12}`(鍵が r でない) | 「Rは入力必須です。」 |
| hex | 数の 123456 | PDF |
| hex | true | 「カラーコードが不正です。」 |
| hex と rgb | 一方が null で、もう一方がある | PDF |
| fontFamily | true | 「フォント種類が不正です。」 |
| title | `"16"`、`" 16"`、`"16 "`、`"16."`、`"+16"`、`".5e2"`、`"1.6e1"`、1E1 | PDF |
| title | 1e400 | 「タイトルフォントサイズは72以下で入力してください。」 |
| title | -0 | 「タイトルフォントサイズは6以上で入力してください。」 |
| title | `"0x10"`、`"NaN"`、`"１６"`(全角) | {} |
| format | 1.50 | 「エクスポート形式が不正です。」 |
| format | `["pdf"]` | {} |
| 本文 | 鍵が `Format` | 「エクスポート形式は入力必須です。」(鍵の大文字と小文字を区別する) |
| 本文 | 同じ鍵を2回(markdown のあとに pdf) | PDF(あとの値を使う) |
| 本文 | 本文のあとに ` x` を足す | PDF(あとに続く字を読まない) |
| pdfSettings、fontSizes、tableHeaderColor、rgb | `""` か `[]` | {} |
| 本文 | 空か `""` | {} |
| 断る本文の errors | 3つの欄が同時に誤り | 鍵ごとのオブジェクト。鍵は `pdfSettings.tableHeaderColor.specifiedOnce`、`pdfSettings.fontSizes.title`、`pdfSettings.fontFamily` |
| 断る本文の errors | rgb の r が範囲の外 | 鍵は `pdfSettings.tableHeaderColor.rgb.red`(Java の欄の名前) |

数の欄に真偽の値を入れた本文と、文字列の欄に指数の付いた数を入れた本文の答えは、記録を残していない。設計では、この2つを比べる検査の筋書きで確かめる。

## 設計の決めごと

### 一般化

- 筋書きの要求に、fixtures の下の JSON のファイルをそのまま本文にする欄を足す。置き換えの spec が置いた、2つのフォントと文字の大きさの要求の本文のファイルを、筋書きに書き写さずに使える。ほかのまとまりの筋書きも、同じ欄で長い本文を送れる
- 筋書きの期待に、答えの本文に含まれるはずの字の並びの欄を足す。版をまたぐ確認は、Markdown の本文に、保存した版で入れた値が出ているかを、この欄で確かめる。JSON でない本文の答えを確かめる、ほかのまとまりの筋書きにも使える
- 版に送る段でも、期待の Content-Type を書けるようにする。今は絶対の URL の段にだけ書ける

### 作るか使うか

- PDF を比べる部品は、poppler-utils の pdftotext、pdffonts、pdftoppm、pdftohtml をそのまま使う。4つは開発環境と CI に入っているので、新しいライブラリもパッケージも要らない
- Content-Disposition のヘッダは、Go の標準の mime.FormatMediaType を使わずに、Spring の ContentDisposition の書き方を写す。mime.FormatMediaType は、日本語の名前に filename*= だけを書き、Java 版の filename="___" の形を作らない
- 互換漢字の直しは、すでに直接の依存の golang.org/x/text の norm を使う

### 簡素化

- 本文を `x-go-type: json.RawMessage` で受け、internal/resume の中で読む。生成した型で読むと、encoding/json が鍵の大文字と小文字を区別せず、型の違う値を読めない本文として断るので、Java 版の断る条件と違う
- 経歴書の受け口の Options と ResumeService を分けず、26の操作を28の操作に広げる。出力の操作も、ログインを求め、経歴書を読む同じ Service の処理だからである
- Accept の行は、Google と GitHub の操作が使う中間処理を、出力の GET の操作でも働かせて読む。同じ値を読む中間処理を2つにしない
- 断る答えと 404 と 400 の誤りは、マスタと経歴書のまとまりが作った *auth.Error の作り方をそのまま使う
