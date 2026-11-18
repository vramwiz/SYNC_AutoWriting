# SYNC_AutoWriting 作業ノート

## 前提

- プロジェクト: `D:\DelphiProg\MyApp\SYNC_AutoWriting`。
- 参照元: `D:\DelphiProg\MyApp\SYNC_WeatherFX`。SDK型定義・項目登録基盤・ビルド設定と作業上の注意を継承する。天気演出の処理・サンプル・Git履歴・IDE個人設定はコピーしない。
- Delphi名 `SYNC_AutoWriting`、日本語名「自動筆記」、グループ「SYNC」。本番は1つのAUF2。
- 仕様は `docs/SPECIFICATION.md`。現在の実装範囲と制限は `docs/IMPLEMENTATION.md`。ユーザー向け操作は `README.md`。
- ユーザー指示によりsetupは参照元の5ファイル（ZIPを含む）をそのままコピーする。WeatherFXの名前・ハッシュ・公開履歴を含むが、今は書き換えたり実行したりしない。
- 現在は開発版v0.1.3。正式初版はv1.0.0からとし、コピー元の公開履歴を引き継がない。

## ビルド

Delphi 37.0 / Win64。IDEで開く場合は `SYNC_AutoWriting.dproj`。設定画面のためVCLを使用する。

プロジェクトルートで以下を実行する。

```powershell
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_AutoWriting.dproj /t:Rebuild /p:Config=Debug /p:Platform=Win64 /fl /flp:"logfile=Win64\LatestVerification\DebugBuild.log;verbosity=normal;encoding=UTF-8"'
.\Tests\run_tests.ps1 -OutputDirectory (Join-Path $PWD 'Win64\LatestVerification\DebugImages')
cmd /c 'call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat" && msbuild SYNC_AutoWriting.dproj /t:Rebuild /p:Config=Release /p:Platform=Win64 /fl /flp:"logfile=Win64\LatestVerification\ReleaseBuild.log;verbosity=normal;encoding=UTF-8"'
.\Tests\run_tests.ps1 -OutputDirectory (Join-Path $PWD 'Win64\LatestVerification\ReleaseImages')
```

- Debug / Releaseとも出力先は **`C:\ProgramData\aviutl2\Plugin\SYNC_AutoWriting\`**。
- DLLを同名のAUF2へコピーし、成功後にDLLを削除する。ReleaseはRSMも削除する。最後にReleaseを配置する。
- DCUは `Win64\Debug\DCU` / `Win64\Release\DCU`。ログ・検査結果は `Win64\LatestVerification`。
- ビルド後イベントは参照元の1行の `copy ... && del ...` を維持する。後続が条件文へ取り込まれる連結へ変更しない。
- デバッガーホストは参照元と同じ `D:\aviutl2_v2.1.16\aviutl2.exe`。依頼なしに変更しない。
- 警告0・エラー0、出力AUF2の更新と最終ハッシュを確認する。MSBuild成功とIDE内の表示確認は区別する。
- SDK・UI・解析ユニット追加時は `.dpr` の `in` と `.dproj` の `DCCReference` を両方更新する。検索パスは `Source\Common`、`Source\Lib`、`Source\Lib\FilterTable`、`Source\Plugin\Filter`、`Source\UI`。

## 学習データ

- Windowsのマイドキュメント既知フォルダー内に `SYNC_AutoWriting` を作成する。実環境での解決先は **`D:\Users\take6\SYNC_AutoWriting`**。パスをコードへ固定しない。
- `Fonts/<SHA-256>/<UTF-16コード>.json`。フォント実体名・太字・斜体・head/nameテーブルのハッシュでフォントを識別する。
- 学習データはスキーマ、フォントID・表示名、対象文字、画ID・順序・方向・128 em基準の正規化座標だけ。元輪郭・マスク・フォントファイルは保存しない。
- 同じ文字の全出現で経路を共有する。UIの変更は即時・原子的に保存し、共有リビジョンで本体の解析キャッシュも無効化する。
- 破損JSONは元ファイルを変更せず推定へ戻し、UIへ理由を表示する。未保存エラーもUIへ通知する。
- 検査用の学習IDはGUIDから一意に生成し、検査後にそのファイルと専用フォルダーだけを削除する。

## ソースと責務

- `SYNC_AutoWriting.dpr`: 4エクスポートと最低対応バージョン2011600。
- `Source/Plugin/Filter/SYNC_AutoWriting_FilterPlugin.pas`: 自動筆記/SYNC、フラグ25、インスタンス所有のロック・描画器・RGBA入出力。
- `Source/Plugin/Filter/AutoWriting_Parameters.pas`: 8つの可視項目と非表示の詳細JSON。設定コールバック中だけ編集APIを借用し、変更した値だけ対象エフェクトへ反映する。
- `Source/Common/AutoWriting_Types.pas`: 設定・文字種・JSON・ホスト改行表現・Unicode単位分解。
- `Source/Common/AutoWriting_Fonts.pas`: GDIのアウトライン対応確認、65階調マスク、フォント識別、文字キャッシュ。
- `Source/Common/AutoWriting_Inference.pas`: 細線化・接続方向から経路を推定、画の順序/反転、元マスクの画素へ露出距離を割り当て。
- `Source/Common/AutoWriting_Editing.pas`: 線分/端点の選択判定、線分途中への補間点挿入と分割、端点の方向をそろえた任意2画の結合、点配列を共有しない履歴スナップショット。
- `Source/Common/AutoWriting_Learning.pas`: マイドキュメントの学習JSON読書き、サイズ・座標検証、原子的置換と共有リビジョン。
- `Source/Common/AutoWriting_Renderer.pas`: 共通の配置・全距離タイムライン・定速移動・ペンの持ち上げ・RGBA合成・4種筆記具。
- `Source/UI/AutoWriting_SettingsForm.pas`: コード生成VCLフォーム。独自プレビューと3ペイン筆順編集。フォームはCreateNewのためDFM不要。
- `Source/Lib`: 参照元と同じSDK型定義と項目登録。型の順序・サイズを変更しない。
- `Tests/AutoWriting_Tests.dpr`: 本番AUF2をロードして描画・元フォント・専用設定ダイアログを検査するEXE。

## 開発上の注意

- ホスト映像を設定UIへ取得しない。UIと本体は同じ描画器を使う。
- 文字形状と経路を別に管理する。完成時は元マスクをすべて表示する。
- 時刻×速度から描画状態を直接求める。オブジェクト長・再生履歴・フレーム間乱数に依存させない。
- 拡大率は完成した配置全体と筆記具の出力変換だけに掛け、距離や完了時刻へ掛けない。
- 文字列/フォント/組版/学習が同じ場合に再解析しない。X/Y・拡大率・透明度・速度は解析キーへ含めない。
- インスタンスごとの画像・DC・フォント・キャッシュを所有者が解放する。ホスト所有ポインターを保持しない。全Cコールバックで例外を捕捉する。
- 日本語の `.pas` / `.dpr` / `.ps1` はUTF-8 BOM付き・CRLF。目的・入出力・所有権・保存対象のコメントを維持し、ユニットは約1,500行以内を目安に責務で分ける。
- IDE・AviUtl2は明示依頼時だけ起動・操作する。検査EXEの専用フォームだけは自動検査で表示・閉鎖する。AviUtl2実機でのFPSと操作感は別途確認する。
- コピー元、AUP2、他プラグイン、setupを変更しない。Gitの初期化・コミット・公開は別途依頼時だけ行う。

## 2026-11-18 初期実装

- SYNC_WeatherFXのnote.mdを参考に新規GUIDでプロジェクトを作成し、出力先・名前・グループをAutoWriting用に設定した。
- 入力文字、座標、拡大率、透明度、ペン速度、4種筆記具、設定ボタンを登録。詳細設定はホストの非表示文字列へ保存する。
- 中心線の自動推定、画間の移動を含む距離ベース描画、元字形マスクによる露出、フォント別学習、プレビュー・筆順編集を実装した。
- 編集には画の分割・結合と経路点ドラッグも追加した。単なる点選択は学習保存せず、変更操作のときだけ保存する。
- Debug本体を検査EXEから読み込み、登録・最低バージョン・元字形との画素一致・逆シーク・速度と拡大率・透明度・合成・縦書き・学習IO・本番設定画面からの文字と筆記具の反映を確認した。
- 最新の確定ビルド・検査記録は `Win64/LatestVerification` と `docs/IMPLEMENTATION.md` を参照する。
- `Tests/run_tests.ps1 -Demo` で本番AUF2から20fpsのPNGを出力できる。`Tests/make_demo.py`（検査用Pillow）で `Sample/auto_writing.gif` と一覧画像を作成する。サンプルは実際のDLL出力で、AI画像や別の描画実装ではない。

## 初期版の最終確認（2026-11-18）

- Win64 Debug / Releaseを同じDPROJからRebuildし、どちらも警告0・エラー0。両構成で本番AUF2の描画・設定画面・学習IOの検査が成功した。
- 独立GDIマスクとの全画素一致と、Debug / Releaseの描画画像11枚のSHA-256一致を確認。画の分割・結合の往復、フォント/太字の識別、重複文字の共有、変更しない小数速度・中間点表記の保持も確認した。
- `setup` の5ファイルと、共通SDK/登録ユニット・ライセンス4ファイルは参照元とSHA-256一致。setupのバッチや公開処理は実行していない。
- 最終配置: `C:\ProgramData\aviutl2\Plugin\SYNC_AutoWriting\SYNC_AutoWriting.auf2`、Release v0.1.0、4,542,976バイト。SHA-256: `705306DCCB0539C0D0BA6D1BF7D10CE0F77680E392C27463CF3CEAC64B2B05BD`。配置先はAUF2だけでDLL/RSMなし。
- 全10ユニットのDPR/DPROJ登録、ソースのUTF-8 BOM/CRLFを確認。記録は `Win64/LatestVerification/VerificationSummary.json`、`ReleaseArtifact.json`、各ビルド・検査ログ、画像照合・コピー照合JSON。
- 本番の専用設定ダイアログだけを検査EXEで開いて自動検査した。IDE・AviUtl2の起動/操作、AUP2の変更、Git操作、公開は行っていない。実ホストでの使用感とFPSは未確認。
- ユーザー仕様の全14章を `docs/SPECIFICATION.md` に保存。高度な縦組み・補助平面文字・毛筆の筆圧・自動筆順の精度など、残る制限は `docs/IMPLEMENTATION.md` に明記した。

## v0.1.1 設定プレビューのちらつき修正（2026-11-18）

- ユーザー報告の強いちらつきに対応。従来のウィンドウを持たないTPaintBoxを、不透明な独立TCustomControlへ変更した。明示的なダブルバッファを有効にし、先行する背景消去で表示済みフレームを空白にしない。文章プレビュー・書き順編集の1文字再生の両方へ適用する。
- 表示用32bit DIBとRGBA配列を再利用し、毎フレームのビットマップ作成・破棄と画像バッファ再確保を避ける。完成した画像だけをBitBltで転送する。
- 専用設定ダイアログを使い、両描画面に背景消去メッセージを20回ずつ送ってもチェック背景が保持されることを確認。Spaceによる1文字再生も検査した。Debug / Releaseとも警告0・エラー0、全検査成功。
- 動画用描画画像11枚はDebug / Release間およびv0.1.0とSHA-256一致。筆記経路・タイムライン・学習データ・SDK型・setupに変更はない。
- 作業時にAviUtl2が本体を読み込んでいたため、DPROJを変えずMSBuildのDCC_ExeOutputを一時的に `Win64/FlickerFix/Debug` / `Release` へ上書きしてビルド・検査した。ユーザーから「終了した」の連絡後、検査済みReleaseを通常のプラグインフォルダーへ配置し、SHA-256一致を確認した。
- 修正ログ・UI確認画像・比較結果は `Win64/FlickerFix`。配置結果とSHA-256は `Win64/LatestVerification/ReleaseArtifact.json` を参照。IDE・AviUtl2の起動/画面操作は行っていない。

## v0.1.2 筆順編集の分割・結合・履歴（2026-11-18）

- ユーザー画像の「自」は、上の短い画と上辺・右縦画が1本に推定されていた。元の点選択式では操作しづらいため、分割モードで線上の任意位置をクリックして切れるようにした。重なりでは選択中の画を優先し、節点の間は補間点を挿入する。
- 結合は一覧の次の画という制限をなくし、任意の2画のつなぐ端点をクリックする方式へ変更。選択した端点どうしがつながるよう、自動的に各経路を反転する。同じ座標の端点も、2回目は結合元を候補から除外して選べる。
- 分割位置の黄色いマーカー・結合待ちの緑リング・モード表示を追加。同じボタンか右クリックで解除できる。通常は線をクリックして画を選び、4px以上のドラッグから点を移動する。
- 元に戻す/やり直すボタンとCtrl+Z/Yを追加。同一文字の50操作まで保持し、別の文字/フォントの選択でリセットする。順序・反転・ドラッグ・分割・結合・自動推定へのリセットに対応し、保存学習の有無も復元する。履歴は点配列を深く複製する。
- `AutoWriting_Editing.pas` をDPR/DPROJ両方へ登録。本番11ユニット。SDK型・通常の出力先・setupは変更しない。
- 実字形「自」の最初の画の分離、4通りの端点方向、非隣接結合、同位置端点、深い履歴コピー、保存と再読込・Undo/Redoを検査。本番UIも未使用の私用文字を使い、クリック分割→Undo→Redo→端点結合→Undoで元の保存状態に戻すところまで検査した。既存の学習ファイルへは書き込んでいない。
- ビルド・検査・UI確認画像・描画比較は `Win64/StrokeEditing`。IDE・AviUtl2の起動/操作は行わず、検査用の専用設定フォームだけを開く。
- Debug / Releaseとも警告0・エラー0、全検査成功。動画描画の11画像は両構成とv0.1.1で一致。AviUtl2が終了していることを確認して、検査済みReleaseを通常の配置先へコピーした。
- 配置済みv0.1.2は4,574,208バイト、SHA-256 `5DBA3AF6556BFE98C03C078B21E225F89BC107D98B5DAF8124214C299D0B080C`。setup5ファイルの不変・全11ユニットの登録・ソースのUTF-8 BOM/CRLFも確認した。

## v0.1.3 点選択・右クリック編集・複数行ドラッグ・閉じると反映（2026-11-18）

- ユーザー指定で右側の操作ボタンを廃止。中央の点選択→右クリック分割、画一覧のCtrl/Shift複数選択→右クリック結合へ変更した。他の操作もメニューとショートカットへ集約した。
- 選択点は画の色を使った直径約25pxの丸と白黒の縁、画番号で表示する。重なった点は22pxの色付きアイコン・画番号・点番号の候補メニューで選ぶ。同じ画が同じ交差位置へ戻る場合も候補を分ける。選択済みの点はドラッグでき、右クリックの候補サブメニューで選び直せる。
- 画一覧は標準の複数選択と自動ドラッグを利用。元の順序を保って選択行をまとめて移動し、行間の挿入先を青い横線と両端の矢印で表示する。VCLはドロップ直前にもDragLeaveで受理可否を確認するため、Leave自体を拒否しない。実際のドロップ位置はコールバックの座標から再計算する。
- 複数画の結合は一覧順に行い、近い端点でつながるよう方向を調整する。未選択行の順序と画IDを保持する。元に戻す/やり直すはこれらの操作にも対応する。
- Ctrl+K分割、Ctrl+J結合、Ctrl+R反転、Alt+上下移動、Ctrl+Z/Y履歴、Ctrl+Shift+R自動推定、Ctrl+A全画選択、Space再生/停止。プレビューや文字入力中に編集ショートカットを奪わないようメニューの有効範囲を切り替える。
- 「適用して閉じる」「キャンセル」を廃止し、×やAlt+F4で閉じると文章・詳細設定を反映する。閉じる前に検証し、変更しない速度と中間点は保持する。
- 本番AUF2の専用UIで、右クリックメニューの実行、重なり候補の選択、複数選択結合、Ctrl+K/Z/Y、複数行ドラッグ、挿入線の表示画素、移動結果とUndo、閉じる時の保存を検査する。ドラッグ検査では検査フォームだけを一時的に最前面へ出し、マウスポインターを移動せず専用キャプチャへメッセージを送る。IDE・AviUtl2の起動/操作は行わない。
- ビルド・検査・UI画像は `Win64/EditorMenus`。既存の学習データ・SDK型・setup・DPROJの通常出力先は変更しない。
- Debug / Releaseとも警告0・エラー0、全検査成功。描画11画像は両構成・v0.1.2と一致。配置済みRelease v0.1.3は4,586,496バイト、SHA-256 `5D209D37EA548A9F9A43BFB5E400A91E1B51B7C9DA80019E00D85B4FC331BC87`。通常配置先との一致、setup5件と共通4件の不変も確認した。
