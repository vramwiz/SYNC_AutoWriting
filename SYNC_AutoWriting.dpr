library SYNC_AutoWriting;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 自動筆記のDLL境界。CコールバックからDelphi例外を漏らさない。

{$ALIGN 8}

uses
  AviUtl2FilterTypes in 'Source\Lib\AviUtl2FilterTypes.pas',
  PluginFilterTable in 'Source\Lib\FilterTable\PluginFilterTable.pas',
  AutoWriting_Types in 'Source\Common\AutoWriting_Types.pas',
  AutoWriting_Reveal in 'Source\Common\AutoWriting_Reveal.pas',
  AutoWriting_Inference in 'Source\Common\AutoWriting_Inference.pas',
  AutoWriting_Editing in 'Source\Common\AutoWriting_Editing.pas',
  AutoWriting_Learning in 'Source\Common\AutoWriting_Learning.pas',
  AutoWriting_Fonts in 'Source\Common\AutoWriting_Fonts.pas',
  AutoWriting_Renderer in 'Source\Common\AutoWriting_Renderer.pas',
  AutoWriting_SettingsForm in 'Source\UI\AutoWriting_SettingsForm.pas',
  AutoWriting_Parameters in 'Source\Plugin\Filter\AutoWriting_Parameters.pas',
  SYNC_AutoWriting_FilterPlugin in 'Source\Plugin\Filter\SYNC_AutoWriting_FilterPlugin.pas';

{$R *.res}

function InitializePlugin(Version: Cardinal): Byte; cdecl;
begin
  Result:=0;
  try if Version<AUTOWRITING_REQUIRED_VERSION then Exit; GetAutoWritingFilterTable; Result:=1 except end;
end;

procedure UninitializePlugin; cdecl;
begin end;

function RequiredVersion: Cardinal; cdecl;
begin Result:=AUTOWRITING_REQUIRED_VERSION end;

function GetFilterPluginTable: PFILTER_PLUGIN_TABLE; cdecl;
begin Result:=nil; try Result:=GetAutoWritingFilterTable except end end;

exports
  RequiredVersion name 'RequiredVersion',
  InitializePlugin name 'InitializePlugin',
  UninitializePlugin name 'UninitializePlugin',
  GetFilterPluginTable name 'GetFilterPluginTable';

begin
end.
