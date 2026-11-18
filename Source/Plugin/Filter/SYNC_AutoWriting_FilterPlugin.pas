unit SYNC_AutoWriting_FilterPlugin;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 自動筆記/SYNCを登録する。エフェクトごとにロック・解析キャッシュ・画像を所有する。
// SDK ABI定義は参照元と同じ。ホストのポインターはコールバック外へ保存しない。

interface

uses AviUtl2FilterTypes;

const AUTOWRITING_REQUIRED_VERSION = 2011600;
function GetAutoWritingFilterTable: PFILTER_PLUGIN_TABLE;

implementation

uses System.SysUtils, System.SyncObjs, Winapi.Windows, PluginFilterTable,
  AutoWriting_Types, AutoWriting_Renderer, AutoWriting_Parameters;

type
  TWritingSession = class
  private
    FLock: TCriticalSection;
    FRenderer: TWritingRenderer;
    FInput,FOutput: TWritingPixels;
  public
    constructor Create;
    destructor Destroy; override;
    function Render(Video: PFILTER_PROC_VIDEO): Byte;
  end;

var Initialized: Boolean;

constructor TWritingSession.Create;
begin inherited; FLock:=TCriticalSection.Create; FRenderer:=TWritingRenderer.Create end;

destructor TWritingSession.Destroy;
begin FRenderer.Free; FLock.Free; inherited end;

function TWritingSession.Render(Video: PFILTER_PROC_VIDEO): Byte;
var W,H: Integer; S: TWritingSettings;
begin
  Result:=0; if not Assigned(Video^.SetImageData) then Exit;
  W:=Video^.Object_^.Width; H:=Video^.Object_^.Height;
  if (W<=0) or (H<=0) then
  begin if Video^.Scene=nil then Exit; W:=Video^.Scene^.Width; H:=Video^.Scene^.Height end;
  if (W<=0) or (H<=0) or (W>8192) or (H>8192) or (Int64(W)*H>AW_MAX_PIXELS) then Exit;
  FLock.Acquire;
  try
    S:=ReadAutoWritingSettings;
    if Assigned(Video^.GetImageData) and (Video^.Object_^.Width=W) and (Video^.Object_^.Height=H) then
    begin SetLength(FInput,W*H); Video^.GetImageData(@FInput[0]) end else FInput:=nil;
    FRenderer.Render(FInput,W,H,Video^.Object_^.Time,S,FOutput);
    Video^.SetImageData(@FOutput[0],W,H); Result:=1;
  finally FLock.Release end;
end;

function WritingProcVideo(Video: PFILTER_PROC_VIDEO): Byte; cdecl;
begin
  Result:=0; if (Video=nil) or (Video^.Object_=nil) or (Video^.UserData=nil) then Exit;
  try Result:=TWritingSession(Video^.UserData).Render(Video)
  except on E: Exception do OutputDebugString(PChar('SYNC_AutoWriting render: '+E.Message)) end;
end;

function WritingCreate(EffectID: Int64): Pointer; cdecl;
begin Result:=nil; try Result:=TWritingSession.Create except end end;

procedure WritingDestroy(EffectID: Int64; UserData: Pointer); cdecl;
begin try TWritingSession(UserData).Free except end end;

function GetAutoWritingFilterTable: PFILTER_PLUGIN_TABLE;
begin
  if not Initialized then
  begin
    SetupPluginTable(FILTER_FLAG_VIDEO or FILTER_FLAG_FILTER or FILTER_FLAG_USERDATA,
      '自動筆記','SYNC','自動筆記 / SYNC_AutoWriting v'+AW_VERSION,WritingProcVideo,nil);
    RegisterAutoWritingParameters; GetPluginTable^.Func_Create:=WritingCreate;
    GetPluginTable^.Func_Destroy:=WritingDestroy; Initialized:=True;
  end;
  Result:=GetPluginTable;
end;

end.
