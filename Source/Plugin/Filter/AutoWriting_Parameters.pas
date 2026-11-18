unit AutoWriting_Parameters;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// AviUtl2の最小パラメーターと設定ダイアログの接続。詳細JSONはホストに保存する。
// ホスト所有文字列は呼出し内で複製し、編集APIのポインターを保持しない。

interface

uses AutoWriting_Types;

procedure RegisterAutoWritingParameters;
function ReadAutoWritingSettings: TWritingSettings;

implementation

uses System.SysUtils, System.Math, System.UITypes, Winapi.Windows, Vcl.Dialogs,
  AviUtl2FilterTypes, PluginFilterTable, AutoWriting_SettingsForm;

var
  TextItem,DetailsItem: TFILTER_ITEM_STRING;
  Tracks: array[0..4] of TFILTER_ITEM_TRACK;
  PenItem: TFILTER_ITEM_SELECT;
  PenOptions: array[0..4] of TFILTER_ITEM_SELECT_ITEM;
  SettingsButton: TFILTER_ITEM_BUTTON;
  HideDetails: TFILTER_ITEM_HIDE_RULE;
  DefaultText,DefaultDetails: string;

const
  PEN_NAMES: array[TPenKind] of PWideChar = ('鉛筆','ボールペン','万年筆','毛筆');

function ReadAutoWritingSettings: TWritingSettings;
begin
  Result:=DefaultWritingSettings;
  if DetailsItem.Value<>nil then ReadSettingsJSON(string(DetailsItem.Value),Result);
  if TextItem.Value<>nil then Result.Text:=DecodeHostText(string(TextItem.Value));
  Result.X:=SafeNumber(Tracks[0].Value,0,-16384,16384); Result.Y:=SafeNumber(Tracks[1].Value,0,-16384,16384);
  Result.Scale:=SafeNumber(Tracks[2].Value,100,0,1000); Result.Transparency:=SafeNumber(Tracks[3].Value,0,0,100);
  Result.Speed:=SafeNumber(Tracks[4].Value,240,1,10000);
  Result.Pen:=TPenKind(EnsureRange(PenItem.Value,0,3));
end;

procedure OpenSettings(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect,Item: PWideChar); cdecl;
var S,Original: TWritingSettings; Target: string;
  Names: array[0..3] of string; OldValues,NewValues: array[0..3] of UTF8String;
  I,J: Integer; P: PAnsiChar; Updated: array[0..3] of Boolean;
  function GetValue(const Name: string; const Fallback: string): UTF8String;
  var Value: PAnsiChar;
  begin
    Result:=UTF8String(Fallback);
    if not Assigned(Edit^.GetObjectItemValue) then Exit;
    Value:=Edit^.GetObjectItemValue(Obj,PChar(Target),PChar(Name));
    if Value<>nil then Result:=UTF8String(Value);
  end;
begin
  if (Edit=nil) or (Obj=nil) or (Effect=nil) or not Assigned(Edit^.SetObjectItemValue) then Exit;
  try
    Target:=Effect; S:=ReadAutoWritingSettings;
    Names[0]:='詳細設定'; Names[1]:='表示文字列'; Names[2]:='ペン種類'; Names[3]:='ペン速度';
    OldValues[0]:=GetValue(Names[0],SettingsJSON(S));
    OldValues[1]:=GetValue(Names[1],EncodeHostText(S.Text));
    OldValues[2]:=GetValue(Names[2],string(PEN_NAMES[S.Pen]));
    OldValues[3]:=GetValue(Names[3],FloatToStr(S.Speed,TFormatSettings.Invariant));
    ReadSettingsJSON(string(OldValues[0]),S); S.Text:=DecodeHostText(string(OldValues[1]));
    for I:=0 to 3 do if string(OldValues[2])=string(PEN_NAMES[TPenKind(I)]) then S.Pen:=TPenKind(I);
    S.Speed:=SafeNumber(StrToFloatDef(string(OldValues[3]),S.Speed,TFormatSettings.Invariant),240,1,10000);
    Original:=S; if not EditWritingSettings(S) then Exit;
    NewValues[0]:=UTF8String(SettingsJSON(S)); NewValues[1]:=UTF8String(EncodeHostText(S.Text));
    NewValues[2]:=UTF8String(PEN_NAMES[S.Pen]); NewValues[3]:=UTF8String(FloatToStr(S.Speed,TFormatSettings.Invariant));
    // ダイアログで変更しなかった速度の中間点やホスト側の表記を保持する。
    if S.Speed=Original.Speed then NewValues[3]:=OldValues[3];
    FillChar(Updated,SizeOf(Updated),0);
    try
      for I:=0 to 3 do
      begin
        if NewValues[I]=OldValues[I] then Continue;
        P:=PAnsiChar(NewValues[I]);
        if not Edit^.SetObjectItemValue(Obj,PChar(Target),PChar(Names[I]),P) then
          raise EInvalidOp.Create('AviUtl2へ設定を反映できません: '+Names[I]);
        Updated[I]:=True;
      end;
    except
      for J:=3 downto 0 do if Updated[J] then
        Edit^.SetObjectItemValue(Obj,PChar(Target),PChar(Names[J]),PAnsiChar(OldValues[J]));
      raise;
    end;
  except
    on E: Exception do
    begin
      OutputDebugString(PChar('SYNC_AutoWriting settings: '+E.Message));
      try MessageDlg(E.Message,mtError,[mbOK],0) except end;
    end;
  end;
end;

procedure RegisterAutoWritingParameters;
var S: TWritingSettings; P: TPenKind;
begin
  S:=DefaultWritingSettings; DefaultText:=EncodeHostText(S.Text); DefaultDetails:=SettingsJSON(S);
  AddString(TextItem,'表示文字列',PChar(DefaultText));
  AddTrack(Tracks[0],'X座標',0,-16384,16384,0.1); AddTrack(Tracks[1],'Y座標',0,-16384,16384,0.1);
  AddTrack(Tracks[2],'拡大率',100,0,1000,0.1); AddTrack(Tracks[3],'透明度',0,0,100,0.1);
  AddTrack(Tracks[4],'ペン速度',240,1,10000,1);
  FillChar(PenOptions,SizeOf(PenOptions),0);
  for P:=Low(P) to High(P) do begin PenOptions[Ord(P)].Name:=PEN_NAMES[P]; PenOptions[Ord(P)].Value:=Ord(P) end;
  AddSelect(PenItem,'ペン種類',Ord(S.Pen),@PenOptions[0]);
  AddButton(SettingsButton,'設定',OpenSettings);
  AddString(DetailsItem,'詳細設定',PChar(DefaultDetails)); AddAlwaysHideRule(HideDetails,'詳細設定');
end;

end.
