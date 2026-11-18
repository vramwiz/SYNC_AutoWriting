# SYNC_AutoWriting の作業規則

- 開始時に `note.md` を読む。仕様は `docs/SPECIFICATION.md`、実装状況は `docs/IMPLEMENTATION.md`。
- 本番は `SYNC_AutoWriting.dproj` / `SYNC_AutoWriting.auf2` の1つ。検査用EXEはこの本番AUF2を読み込む。
- Delphi 37.0、Win64 Debug / ReleaseをMSBuildでビルドし、警告0・エラー0とAUF2の更新を確認する。
- 出力先は `C:\ProgramData\aviutl2\Plugin\SYNC_AutoWriting\`。最後にReleaseを配置する。
- ユニット追加時は `.dpr` の `in`、`.dproj` の `DCCReference` と必要な検索パスを更新する。
- 日本語を含む `.pas` / `.dpr` / `.ps1` はUTF-8 BOM付き・CRLF。公開処理の入出力と所有権を記載する。
- UI・描画・解析・学習保存を分け、1ユニット約1,500行以内を目安とする。コード生成フォームはDFM不要。
- ホスト所有ポインターはコールバックの外へ保持しない。例外をDLL境界から漏らさない。
- IDE・AviUtl2の起動と画面操作は明示依頼時だけ行う。通常の検査はコマンドラインで行う。
- 参照元SYNC_WeatherFX、ユーザーのAUP2、他プラグインを変更しない。
- `setup` はユーザー指定で参照元をそのままコピーする。内容変更や配布処理の実行は別途依頼時だけ。
- 学習先はWindowsのマイドキュメント既知フォルダー内 `SYNC_AutoWriting`。フォントや元輪郭を保存しない。
- 正式初版は `v1.0.0`。開発版番号とコピー元setupの公開履歴を正式配布へ転用しない。
