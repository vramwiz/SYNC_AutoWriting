program AutoWriting_Benchmark;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 本番AUF2をフルHD・入力なしで計測する。ホストや既存学習へ書き込まない。
// プラグイン所有パラメーターはLoadLibrary〜FreeLibraryの間だけ借用する。
{$APPTYPE CONSOLE}
uses System.SysUtils, System.Classes, System.Math, System.JSON, System.IOUtils,
  System.Diagnostics, System.Generics.Collections, Winapi.Windows,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  AutoWriting_Types in '..\Source\Common\AutoWriting_Types.pas';
type
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TProfile = record Frames,LayoutTicks,ClearTicks,InkTicks,ShadowTicks,PenTicks,PenPixels,ShadowPixels: Int64 end;
  TReset = procedure; cdecl;
  TRead = procedure(out Profile: TProfile); cdecl;
  TFullScan = procedure(Enabled: Integer); cdecl;
  TItem = record Kind,Name: PWideChar end;
  PItem = ^TItem;
var
  Module: HMODULE; Table: PFILTER_PLUGIN_TABLE; GetTable: TGetTable; Reset: TReset; Read: TRead; FullScan: TFullScan;
  Video: TFILTER_PROC_VIDEO; Obj: TOBJECT_INFO; Scene: TSCENE_INFO; Session: Pointer;
  TextItem,DetailsItem: PFILTER_ITEM_STRING; PenItem: PFILTER_ITEM_SELECT;
  SizeTrack,AngleTrack,LightXTrack,LightYTrack: PFILTER_ITEM_TRACK;
  TextBacking,DetailsBacking: string; OutputCalls: Integer;
  Capture: Boolean; Captured: TWritingPixels;

procedure SetImage(Buffer: PPIXEL_RGBA; W,H: Integer); cdecl;
begin
  if (Buffer=nil) or (W<>1920) or (H<>1080) then Halt(3); Inc(OutputCalls);
  if Capture then begin SetLength(Captured,W*H); Move(Buffer^,Captured[0],W*H*4) end;
end;

procedure Configure(const S: TWritingSettings);
var Choice: ^TFILTER_ITEM_SELECT_ITEM; Found: Boolean;
begin
  TextBacking:=EncodeHostText(S.Text); DetailsBacking:=SettingsJSON(S);
  TextItem^.Value:=PChar(TextBacking); DetailsItem^.Value:=PChar(DetailsBacking);
  Choice:=Pointer(PenItem^.List); Found:=False;
  while Choice^.Name<>nil do begin
    if string(Choice^.Name)=string(AW_PEN_NAMES[S.Pen]) then begin PenItem^.Value:=Choice^.Value; Found:=True; Break end;
    Inc(Choice);
  end;
  if not Found then raise Exception.Create('Pen choice unavailable');
  SizeTrack^.Value:=S.PenSize*100; AngleTrack^.Value:=S.PenAngle;
  LightXTrack^.Value:=S.LightX; LightYTrack^.Value:=S.LightY;
end;

procedure RunCase(const Name: string; Kind: TPenKind; Size: Double; Animated: Boolean; Cases: TJSONArray);
const Count=48;
var S: TWritingSettings; I: Integer; Tick: Int64; Times,Sorted: TArray<Double>;
  Total,Factor: Double; Profile: TProfile; J: TJSONObject;
begin
  S:=DefaultWritingSettings; S.Text:='自動筆記'+sLineBreak+'羽ペンの描画速度を計測します。'; S.Pen:=Kind; S.PenSize:=Size;
  Configure(S); for I:=0 to 3 do begin Obj.Time:=I/30; if Table^.Func_Proc_Video(@Video)<>1 then raise Exception.Create('Warm-up failed') end;
  if Assigned(Reset) then Reset; SetLength(Times,Count); Total:=0;
  for I:=0 to Count-1 do begin
    if Animated then begin SizeTrack^.Value:=100+I*0.5; AngleTrack^.Value:=20+I;
      LightXTrack^.Value:=-100+I; LightYTrack^.Value:=-100-I end;
    Obj.Time:=I/30; Tick:=TStopwatch.GetTimeStamp;
    if Table^.Func_Proc_Video(@Video)<>1 then raise Exception.Create('Render failed');
    Times[I]:=(TStopwatch.GetTimeStamp-Tick)*1000/TStopwatch.Frequency; Total:=Total+Times[I];
  end;
  Sorted:=Copy(Times); TArray.Sort<Double>(Sorted); J:=TJSONObject.Create; Cases.Add(J);
  J.AddPair('name',Name); J.AddPair('frames',TJSONNumber.Create(Count));
  J.AddPair('mean_ms',TJSONNumber.Create(Total/Count)); J.AddPair('median_ms',TJSONNumber.Create(Sorted[Count div 2]));
  J.AddPair('p95_ms',TJSONNumber.Create(Sorted[Floor((Count-1)*0.95)]));
  if Assigned(Read) then begin
    Read(Profile); Factor:=1000/TStopwatch.Frequency/Max(Int64(1),Profile.Frames);
    J.AddPair('layout_ms',TJSONNumber.Create(Profile.LayoutTicks*Factor)); J.AddPair('clear_ms',TJSONNumber.Create(Profile.ClearTicks*Factor));
    J.AddPair('ink_ms',TJSONNumber.Create(Profile.InkTicks*Factor)); J.AddPair('shadow_ms',TJSONNumber.Create(Profile.ShadowTicks*Factor));
    J.AddPair('pen_ms',TJSONNumber.Create(Profile.PenTicks*Factor));
    J.AddPair('pen_bbox_pixels',TJSONNumber.Create(Profile.PenPixels/Max(Int64(1),Profile.Frames)));
    J.AddPair('shadow_bbox_pixels',TJSONNumber.Create(Profile.ShadowPixels/Max(Int64(1),Profile.Frames)));
  end;
  Writeln(Format('%s: mean %.3f ms, p95 %.3f ms',[Name,Total/Count,Sorted[Floor((Count-1)*0.95)]],TFormatSettings.Invariant));
end;

procedure Bind;
var P: PPointer; Name,Kind: string;
begin
  P:=PPointer(Table^.Items);
  while P^<>nil do begin
    Name:=PItem(P^)^.Name; Kind:=PItem(P^)^.Kind;
    if Name='表示文字列' then TextItem:=PFILTER_ITEM_STRING(P^);
    if (Name='詳細設定') and (Kind='string') then DetailsItem:=PFILTER_ITEM_STRING(P^);
    if Name='ペン種類' then PenItem:=PFILTER_ITEM_SELECT(P^);
    if Name='ペンサイズ' then SizeTrack:=PFILTER_ITEM_TRACK(P^);
    if Name='ペン角度' then AngleTrack:=PFILTER_ITEM_TRACK(P^);
    if Name='光源X' then LightXTrack:=PFILTER_ITEM_TRACK(P^);
    if Name='光源Y' then LightYTrack:=PFILTER_ITEM_TRACK(P^);
    Inc(P);
  end;
  if (TextItem=nil) or (DetailsItem=nil) or (PenItem=nil) or (SizeTrack=nil) or (AngleTrack=nil) or
    (LightXTrack=nil) or (LightYTrack=nil) then raise Exception.Create('Missing production parameters');
end;

procedure VerifyQuillBounds(J: TJSONObject);
const Angles: array[0..8] of Double=(-180,-135,-90,-35,0,35,90,135,180);
  Sizes: array[0..2] of Double=(0.3,1,3);
var S: TWritingSettings; Angle,Size: Double; Reference: TWritingPixels; Count: Integer;
begin
  if not Assigned(FullScan) then Exit;
  Capture:=True; Count:=0;
  try
    S:=DefaultWritingSettings; S.Text:='自動筆記'; S.Pen:=pkQuill; Obj.Time:=1;
    for Angle in Angles do for Size in Sizes do begin
      S.PenAngle:=Angle; S.PenSize:=Size; Configure(S); FullScan(1);
      if Table^.Func_Proc_Video(@Video)<>1 then raise Exception.Create('Reference render failed'); Reference:=Copy(Captured);
      FullScan(0); if Table^.Func_Proc_Video(@Video)<>1 then raise Exception.Create('Optimized render failed');
      if not CompareMem(@Reference[0],@Captured[0],Length(Reference)*4) then
        raise Exception.CreateFmt('Bounds clipped quill: angle %.2f, size %.2f',[Angle,Size]);
      Inc(Count);
    end;
  finally Capture:=False; Captured:=nil; FullScan(0) end;
  J.AddPair('bounds_pixel_checks',TJSONNumber.Create(Count)); J.AddPair('bounds_byte_identical',TJSONBool.Create(True));
  Writeln('PASS quill full-scan reference matches optimized bounds: ',Count,' angle/size cases');
end;

var J: TJSONObject; Cases,Choices: TJSONArray; Choice: ^TFILTER_ITEM_SELECT_ITEM; Item: TJSONObject;
begin
  Module:=0; Session:=nil; J:=nil;
  try
    if ParamCount<2 then raise Exception.Create('Usage: AutoWriting_Benchmark.exe plugin.auf2 output.json');
    Module:=LoadLibrary(PChar(ExpandFileName(ParamStr(1)))); if Module=0 then RaiseLastOSError;
    @GetTable:=GetProcAddress(Module,'GetFilterPluginTable'); if not Assigned(GetTable) then raise Exception.Create('Missing table');
    @Reset:=GetProcAddress(Module,'ResetWritingRenderProfile'); @Read:=GetProcAddress(Module,'ReadWritingRenderProfile');
    @FullScan:=GetProcAddress(Module,'SetWritingProfileFullScan');
    Table:=GetTable; Bind; Session:=Table^.Func_Create(81); if Session=nil then raise Exception.Create('No session');
    FillChar(Video,SizeOf(Video),0); FillChar(Obj,SizeOf(Obj),0); FillChar(Scene,SizeOf(Scene),0);
    Obj.Width:=1920; Obj.Height:=1080; Scene.Width:=1920; Scene.Height:=1080; Scene.Rate:=30; Scene.Scale:=1;
    Video.Object_:=@Obj; Video.Scene:=@Scene; Video.UserData:=Session; Video.SetImageData:=SetImage;
    J:=TJSONObject.Create; Cases:=TJSONArray.Create; J.AddPair('cases',Cases); J.AddPair('plugin',ExpandFileName(ParamStr(1)));
    J.AddPair('profile_build',TJSONBool.Create(Assigned(Read))); J.AddPair('resolution','1920x1080');
    Choices:=TJSONArray.Create; J.AddPair('choices',Choices); Choice:=Pointer(PenItem^.List);
    while Choice^.Name<>nil do begin Item:=TJSONObject.Create; Item.AddPair('name',string(Choice^.Name));
      Item.AddPair('value',TJSONNumber.Create(Choice^.Value)); Choices.Add(Item); Inc(Choice) end;
    VerifyQuillBounds(J);
    RunCase('none_100',pkNone,1,False,Cases); RunCase('fountain_100',pkFountain,1,False,Cases);
    RunCase('quill_100',pkQuill,1,False,Cases); RunCase('quill_300',pkQuill,3,False,Cases);
    RunCase('quill_animated',pkQuill,1,True,Cases);
    ForceDirectories(ExtractFileDir(ExpandFileName(ParamStr(2)))); TFile.WriteAllText(ParamStr(2),J.ToJSON,TEncoding.UTF8);
  except on E: Exception do begin Writeln('FAIL: ',E.Message); ExitCode:=1 end end;
  J.Free; if Session<>nil then Table^.Func_Destroy(81,Session); if Module<>0 then FreeLibrary(Module);
end.
