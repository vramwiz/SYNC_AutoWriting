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
  TextItem: TFILTER_ITEM_TEXT;
  DetailsItem: TFILTER_ITEM_STRING;
  Tracks: array[0..9] of TFILTER_ITEM_TRACK;
  PenItem: TFILTER_ITEM_SELECT;
  InkColorItem: TFILTER_ITEM_COLOR;
  PenOptions: array[0..6] of TFILTER_ITEM_SELECT_ITEM;
  SettingsButton: TFILTER_ITEM_BUTTON;
  PenGroup,PenGroupEnd: TFILTER_ITEM_GROUP;
  HideDetails: TFILTER_ITEM_HIDE_RULE;
  DefaultText,DefaultDetails: string;

function ReadAutoWritingSettings: TWritingSettings;
begin
  Result:=DefaultWritingSettings;
  if DetailsItem.Value<>nil then ReadSettingsJSON(string(DetailsItem.Value),Result);
  // text項目のValueは実際の改行を含む。編集APIのエイリアス表記とは分けて扱う。
  if TextItem.Value<>nil then Result.Text:=Copy(string(TextItem.Value),1,AW_MAX_TEXT);
  Result.X:=SafeNumber(Tracks[0].Value,0,-16384,16384); Result.Y:=SafeNumber(Tracks[1].Value,0,-16384,16384);
  Result.Scale:=SafeNumber(Tracks[2].Value,100,0,1000); Result.Transparency:=SafeNumber(Tracks[3].Value,0,0,100);
  Result.Speed:=SafeNumber(Tracks[4].Value,240,1,10000);
  Result.MoveSpeed:=SafeNumber(Tracks[9].Value,0,0,10000);
  Result.PenAngle:=SafeNumber(Tracks[5].Value,35,-180,180);
  Result.LightX:=SafeNumber(Tracks[6].Value,-100,-400,400); Result.LightY:=SafeNumber(Tracks[7].Value,-100,-400,400);
  Result.PenSize:=SafeNumber(Tracks[8].Value,100,30,300)/100;
  Result.Pen:=PenFromChoiceValue(PenItem.Value);
  Result.InkColor:=(Cardinal(InkColorItem.R) shl 16) or (Cardinal(InkColorItem.G) shl 8) or InkColorItem.B;
end;

procedure OpenSettings(Edit: PEDIT_SECTION; Obj: OBJECT_HANDLE; Effect,Item: PWideChar); cdecl;
var S,Original,Details,Current,Stored: TWritingSettings; Target: string;
  Names: array[0..9] of string; OldValues,NewValues: array[0..9] of UTF8String;
  I,J: Integer; P: PAnsiChar; Updated: array[0..9] of Boolean;
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
    Target:=Effect; S:=ReadAutoWritingSettings; Current:=S;
    Names[0]:='詳細設定'; Names[1]:='表示文字列'; Names[2]:='ペン種類'; Names[3]:='ペン速度'; Names[4]:='ペン角度';
    Names[5]:='光源X'; Names[6]:='光源Y'; Names[7]:='ペンサイズ';
    Names[8]:='文字色'; Names[9]:='ペンの移動速度';
    OldValues[0]:=GetValue(Names[0],SettingsJSON(S));
    OldValues[1]:=GetValue(Names[1],EncodeHostText(S.Text));
    OldValues[2]:=GetValue(Names[2],string(AW_PEN_NAMES[S.Pen]));
    OldValues[3]:=GetValue(Names[3],FloatToStr(S.Speed,TFormatSettings.Invariant));
    OldValues[4]:=GetValue(Names[4],FloatToStr(S.PenAngle,TFormatSettings.Invariant));
    OldValues[5]:=GetValue(Names[5],FloatToStr(S.LightX,TFormatSettings.Invariant));
    OldValues[6]:=GetValue(Names[6],FloatToStr(S.LightY,TFormatSettings.Invariant));
    OldValues[7]:=GetValue(Names[7],FloatToStr(S.PenSize*100,TFormatSettings.Invariant));
    OldValues[8]:=GetValue(Names[8],IntToHex(S.InkColor,6));
    OldValues[9]:=GetValue(Names[9],FloatToStr(S.MoveSpeed,TFormatSettings.Invariant));
    ReadSettingsJSON(string(OldValues[0]),S); S.Text:=DecodeHostText(string(OldValues[1]));
    Stored:=S;
    for I:=Ord(Low(TPenKind)) to Ord(High(TPenKind)) do
      if string(OldValues[2])=string(AW_PEN_NAMES[TPenKind(I)]) then S.Pen:=TPenKind(I);
    S.Speed:=SafeNumber(StrToFloatDef(string(OldValues[3]),S.Speed,TFormatSettings.Invariant),240,1,10000);
    S.MoveSpeed:=SafeNumber(StrToFloatDef(string(OldValues[9]),Current.MoveSpeed,TFormatSettings.Invariant),0,0,10000);
    S.PenAngle:=SafeNumber(StrToFloatDef(string(OldValues[4]),Current.PenAngle,TFormatSettings.Invariant),35,-180,180);
    S.LightX:=SafeNumber(StrToFloatDef(string(OldValues[5]),Current.LightX,TFormatSettings.Invariant),-100,-400,400);
    S.LightY:=SafeNumber(StrToFloatDef(string(OldValues[6]),Current.LightY,TFormatSettings.Invariant),-100,-400,400);
    S.PenSize:=SafeNumber(StrToFloatDef(string(OldValues[7]),Current.PenSize*100,TFormatSettings.Invariant),100,30,300)/100;
    S.InkColor:=Cardinal(StrToIntDef('$'+string(OldValues[8]),Integer(Current.InkColor))) and $FFFFFF;
    Original:=S; if not EditWritingSettings(S) then Exit;
    Details:=S; if S.PenAngle=Original.PenAngle then Details.PenAngle:=Stored.PenAngle;
    if S.LightX=Original.LightX then Details.LightX:=Stored.LightX;
    if S.LightY=Original.LightY then Details.LightY:=Stored.LightY;
    if S.PenSize=Original.PenSize then Details.PenSize:=Stored.PenSize;
    if S.InkColor=Original.InkColor then Details.InkColor:=Stored.InkColor;
    NewValues[0]:=UTF8String(SettingsJSON(Details)); NewValues[1]:=UTF8String(EncodeHostText(S.Text));
    NewValues[2]:=UTF8String(AW_PEN_NAMES[S.Pen]); NewValues[3]:=UTF8String(FloatToStr(S.Speed,TFormatSettings.Invariant));
    NewValues[4]:=UTF8String(FloatToStr(S.PenAngle,TFormatSettings.Invariant));
    NewValues[5]:=UTF8String(FloatToStr(S.LightX,TFormatSettings.Invariant));
    NewValues[6]:=UTF8String(FloatToStr(S.LightY,TFormatSettings.Invariant));
    NewValues[7]:=UTF8String(FloatToStr(S.PenSize*100,TFormatSettings.Invariant));
    NewValues[8]:=UTF8String(IntToHex(S.InkColor,6));
    NewValues[9]:=UTF8String(FloatToStr(S.MoveSpeed,TFormatSettings.Invariant));
    // ダイアログで変更しなかった数値の中間点やホスト側の表記を保持する。
    if S.Speed=Original.Speed then NewValues[3]:=OldValues[3];
    if S.MoveSpeed=Original.MoveSpeed then NewValues[9]:=OldValues[9];
    if S.PenAngle=Original.PenAngle then NewValues[4]:=OldValues[4];
    if S.LightX=Original.LightX then NewValues[5]:=OldValues[5];
    if S.LightY=Original.LightY then NewValues[6]:=OldValues[6];
    if S.PenSize=Original.PenSize then NewValues[7]:=OldValues[7];
    if S.InkColor=Original.InkColor then NewValues[8]:=OldValues[8];
    FillChar(Updated,SizeOf(Updated),0);
    try
      for I:=0 to High(Names) do
      begin
        if NewValues[I]=OldValues[I] then Continue;
        P:=PAnsiChar(NewValues[I]);
        if not Edit^.SetObjectItemValue(Obj,PChar(Target),PChar(Names[I]),P) then
          raise EInvalidOp.Create('AviUtl2へ設定を反映できません: '+Names[I]);
        Updated[I]:=True;
      end;
    except
      for J:=High(Names) downto 0 do if Updated[J] then
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
var S: TWritingSettings; P: TPenKind; I: Integer;
begin
  S:=DefaultWritingSettings; DefaultText:=S.Text; DefaultDetails:=SettingsJSON(S);
  AddText(TextItem,'表示文字列',PChar(DefaultText));
  AddTrack(Tracks[0],'X座標',0,-16384,16384,0.1); AddTrack(Tracks[1],'Y座標',0,-16384,16384,0.1);
  AddTrack(Tracks[2],'拡大率',100,0,1000,0.1); AddTrack(Tracks[3],'透明度',0,0,100,0.1);
  AddColor(InkColorItem,'文字色',255,255,255,0);
  AddString(DetailsItem,'詳細設定',PChar(DefaultDetails)); AddAlwaysHideRule(HideDetails,'詳細設定');
  AddGroup(PenGroup,'ペン',1);
  FillChar(PenOptions,SizeOf(PenOptions),0);
  for I:=Low(AW_PEN_ORDER) to High(AW_PEN_ORDER) do begin
    P:=AW_PEN_ORDER[I]; PenOptions[I].Name:=AW_PEN_NAMES[P]; PenOptions[I].Value:=PenChoiceValue(P);
  end;
  AddSelect(PenItem,'ペン種類',Ord(S.Pen),@PenOptions[0]);
  // 保存済み項目名とトラックの割当てを維持し、ペンの種類・速度・サイズ・角度・光源をまとめる。
  AddTrack(Tracks[4],'ペン速度',240,1,10000,1);
  AddTrack(Tracks[9],'ペンの移動速度',S.MoveSpeed,0,10000,1);
  AddTrack(Tracks[8],'ペンサイズ',100,30,300,0.01);
  AddTrack(Tracks[5],'ペン角度',S.PenAngle,-180,180,0.1);
  AddTrack(Tracks[6],'光源X',S.LightX,-400,400,1); AddTrack(Tracks[7],'光源Y',S.LightY,-400,400,1);
  AddGroup(PenGroupEnd,#0,1);
  AddButton(SettingsButton,'設定',OpenSettings);
end;

end.
