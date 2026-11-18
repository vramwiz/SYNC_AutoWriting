# ライセンスと共通基盤の由来

自動筆記（SYNC_AutoWriting）: Copyright (c) 2026 VRAMの魔術師

ソースコードは参照元と同じGNU General Public License v3.0（GPL-3.0-only）です。全文は [LICENSE](LICENSE)。SDK由来の定義にはMITライセンスの表示も維持します。

## AviUtl ExEdit2 Plugin SDK

- Copyright (c) 2025 Kenkun
- MIT License
- 対象: `Source/Lib/AviUtl2FilterTypes.pas` の型定義、コールバック、編集APIのABI。
- 全文: [ThirdParty/LICENSE.AviUtl2-SDK.txt](ThirdParty/LICENSE.AviUtl2-SDK.txt)

## 継承元

- **SYNC_WeatherFX**: プロジェクト、Win64ビルド設定・イベント、DLL公開関数、SDK型定義、項目登録処理、作業規則の直接の参照元。天気演出本体・画像は含みません。
- **SYNC_AquaFX / SYNC_ParticleFX / SYNC_Mine / SYNC_PhotoShot / SYNC_Nicomea**: 参照元を経由した共通基盤とビルド構成の由来。
- **Syncroh2 / SYNC_Lyrics**: `PluginFilterTable.pas` の登録処理の由来。
- **Aul2AudioFilter**: 編集APIで標準項目へ反映する方式の由来。

setupの配布処理はWeatherFXを参照して継承し、SYNC_AutoWriting用に製品名・パス・カタログとバージョン検証を変更しています。

文字中心線の細線化にはZhang-Suenの2段階削除条件を独自実装しています。外部実装のソースコード・学習モデル・筆順辞書は同梱していません。

Delphi RTL/VCLとWindows GDIを使用します。フォント、AviUtl2本体、Delphi開発環境、外部のペン画像は同梱しません。

設定画面にはDelphi 37.0付属のVCLスタイル「Windows Modern Dark」（Embarcadero）を使用し、AUF2のリソースへ組み込んでいます。スタイルの参照元はRAD Studioの `Styles/WindowsModernDark.vsf` です。
