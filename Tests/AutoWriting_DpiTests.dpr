program AutoWriting_DpiTests;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// 本番AUF2の専用設定フォームだけを開き、DPI変更と画面内への配置を検査する。
// ホストやユーザーのプロジェクト・学習データは変更しない。
{$APPTYPE CONSOLE}

uses System.SysUtils, System.IOUtils, System.Types,
  Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, Winapi.MultiMon, Vcl.Graphics, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas';

type
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TUninitialize = procedure; cdecl;
  PItem = ^TItem;
  TItem = record Kind,Name: PWideChar end;

function PrintWindow(Wnd: HWND; DC: HDC; Flags: UINT): BOOL; stdcall; external 'user32.dll';

var
  Dialog,Memo,Scroll,Page,PenSize,Replay,Characters,Strokes: HWND;
  TimerID: UINT_PTR;
  Stage,Ticks,Checks,InitialDpi: Integer;
  Failure,OutputDirectory: string;

procedure Check(Value: Boolean; const MessageText: string);
begin Inc(Checks); if not Value then raise Exception.Create(MessageText) end;

function FindDialog(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var Name: array[0..127] of Char;
begin
  GetClassName(Wnd,Name,Length(Name));
  if string(Name)='TWritingSettingsForm' then Dialog:=Wnd;
  Result:=True;
end;

function FindChild(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var Name,Caption: array[0..127] of Char;
begin
  GetClassName(Wnd,Name,Length(Name)); GetWindowText(Wnd,Caption,Length(Caption));
  if string(Name)='TMemo' then Memo:=Wnd;
  if string(Name)='TScrollBox' then Scroll:=Wnd;
  if string(Name)='TPageControl' then Page:=Wnd;
  if string(Name)='TNumberBox' then PenSize:=Wnd;
  if string(Name)='TListBox' then Characters:=Wnd;
  if string(Name)='TWritingStrokeListBox' then Strokes:=Wnd;
  if (string(Name)='TButton') and (string(Caption)='先頭から再生') then Replay:=Wnd;
  Result:=True;
end;

procedure Capture(const Name: string);
var Bitmap: TBitmap; PNG: TPngImage; R: TRect;
begin
  GetWindowRect(Dialog,R); Bitmap:=TBitmap.Create; PNG:=TPngImage.Create;
  try
    Bitmap.SetSize(R.Width,R.Height);
    Check(PrintWindow(Dialog,Bitmap.Canvas.Handle,0),'Cannot capture DPI dialog');
    PNG.Assign(Bitmap); PNG.SaveToFile(TPath.Combine(OutputDirectory,Name));
  finally PNG.Free; Bitmap.Free end;
end;

procedure CheckLayout(Dpi: Integer);
var R,Client,WindowRect: TRect; LF: TLogFont; Info: TMonitorInfo;
begin
  Check((Memo<>0) and (Scroll<>0) and (Page<>0) and (PenSize<>0) and (Replay<>0),'Missing DPI controls');
  GetWindowRect(Memo,R); GetClientRect(Scroll,Client);
  MapWindowPoints(0,Scroll,R,2);
  Check(Abs(R.Width-MulDiv(304,Dpi,96))<=2,'Memo width did not follow the DPI');
  Check((R.Left>=0) and (R.Right<=Client.Right),'Memo is clipped by its scroll pane');
  Check(GetObject(HFONT(SendMessage(PenSize,WM_GETFONT,0,0)),SizeOf(LF),@LF)<>0,'Missing input font');
  GetWindowRect(PenSize,R);
  Check((Abs(LF.lfHeight)>=MulDiv(12,Dpi,96)) and (R.Height>=Abs(LF.lfHeight)+MulDiv(4,Dpi,96)),
    'Input font and control height use different DPI scales');
  GetWindowRect(Replay,R); GetClientRect(GetParent(Replay),Client); MapWindowPoints(0,GetParent(Replay),R,2);
  Check((R.Top>=0) and (R.Right<=Client.Right) and (R.Bottom<=Client.Bottom),'Footer button is clipped');
  Info.cbSize:=SizeOf(Info); Check(GetMonitorInfo(MonitorFromWindow(Dialog,MONITOR_DEFAULTTONEAREST),@Info),'No monitor');
  GetWindowRect(Dialog,WindowRect);
  Check((WindowRect.Left>=Info.rcWork.Left) and (WindowRect.Top>=Info.rcWork.Top) and
    (WindowRect.Right<=Info.rcWork.Right) and (WindowRect.Bottom<=Info.rcWork.Bottom),
    Format('Dialog exceeds monitor work area at %d DPI: window %d,%d,%d,%d; work %d,%d,%d,%d',
      [Dpi,WindowRect.Left,WindowRect.Top,WindowRect.Right,WindowRect.Bottom,
       Info.rcWork.Left,Info.rcWork.Top,Info.rcWork.Right,Info.rcWork.Bottom]));
  Writeln('PASS settings layout at ',Dpi,' DPI');
end;

procedure ChangeDpi(Dpi: Integer);
var R: TRect; Header: TNMHdr;
begin
  SendMessage(Page,TCM_SETCURSEL,0,0);
  FillChar(Header,SizeOf(Header),0); Header.hwndFrom:=Page; Header.idFrom:=GetDlgCtrlID(Page); Header.code:=TCN_SELCHANGE;
  SendMessage(GetParent(Page),WM_NOTIFY,Header.idFrom,LPARAM(@Header));
  GetWindowRect(Dialog,R); R.Right:=R.Left+MulDiv(1140,Dpi,96); R.Bottom:=R.Top+MulDiv(840,Dpi,96);
  SendMessage(Dialog,WM_DPICHANGED,WPARAM(Dpi or (Dpi shl 16)),LPARAM(@R));
end;

procedure Tick(Wnd: HWND; Msg: UINT; Event: UINT_PTR; Time: DWORD); stdcall;
var Dpi: Integer; Header: TNMHdr;
begin
  try
    Inc(Ticks); if Ticks>40 then raise Exception.Create('DPI test timed out');
    if Dialog=0 then EnumThreadWindows(GetCurrentThreadId,@FindDialog,0);
    if Dialog=0 then Exit;
    EnumChildWindows(Dialog,@FindChild,0);
    if Stage=0 then begin
      InitialDpi:=GetDpiForWindow(Dialog); CheckLayout(InitialDpi); Capture('dpi_initial.png');
    end
    else if Stage<=3 then begin
      Dpi:=96; if Stage=2 then Dpi:=144 else if Stage=3 then Dpi:=192;
      ChangeDpi(Dpi); CheckLayout(Dpi); Capture(Format('dpi_%d_preview.png',[Dpi]));
      if Dpi=192 then begin
        SendMessage(Scroll,WM_VSCROLL,SB_BOTTOM,0);
        Check(GetScrollPos(Scroll,SB_VERT)>0,'Settings cannot scroll to the lower controls');
        Capture('dpi_192_scrolled.png'); SendMessage(Scroll,WM_VSCROLL,SB_TOP,0);
      end;
    end
    else if Stage=4 then begin
      SendMessage(Page,TCM_SETCURSEL,1,0);
      FillChar(Header,SizeOf(Header),0); Header.hwndFrom:=Page; Header.idFrom:=GetDlgCtrlID(Page); Header.code:=TCN_SELCHANGE;
      SendMessage(GetParent(Page),WM_NOTIFY,Header.idFrom,LPARAM(@Header));
    end
    else if Stage=5 then begin
      Check((Characters<>0) and (Strokes<>0),'Missing editor lists');
      Check(SendMessage(Characters,LB_GETITEMHEIGHT,0,0)=96,'Character rows did not scale to 200 percent');
      Check(SendMessage(Strokes,LB_GETITEMHEIGHT,0,0)=96,'Stroke rows did not scale to 200 percent');
      Capture('dpi_192_editor.png');
      ChangeDpi(96); CheckLayout(96); Capture('dpi_96_roundtrip.png');
      KillTimer(0,TimerID); TimerID:=0; PostMessage(Dialog,WM_CLOSE,0,0);
    end;
    Inc(Stage);
  except on E: Exception do begin
    Failure:=E.Message; KillTimer(0,TimerID); TimerID:=0;
    if Dialog<>0 then Capture('dpi_failure.png');
    if Dialog<>0 then PostMessage(Dialog,WM_CLOSE,0,0);
  end end;
end;

function SetValue(Obj: OBJECT_HANDLE; Effect,Item: PWideChar; Value: PAnsiChar): Boolean; cdecl;
begin Result:=True end;

var Module: HMODULE; GetTable: TGetTable; Initialize: TInitialize; Uninitialize: TUninitialize;
  Table: PFILTER_PLUGIN_TABLE; Item: PPointer; Button: PFILTER_ITEM_BUTTON; Edit: TEDIT_SECTION;
  PreviousContext: DPI_AWARENESS_CONTEXT;
begin
  Module:=0; PreviousContext:=SetThreadDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
  try
    if ParamCount<>2 then raise Exception.Create('Usage: AutoWriting_DpiTests.exe plugin.auf2 output-directory');
    OutputDirectory:=ExpandFileName(ParamStr(2)); ForceDirectories(OutputDirectory);
    Module:=LoadLibrary(PChar(ExpandFileName(ParamStr(1)))); Check(Module<>0,'Cannot load production AUF2');
    @GetTable:=GetProcAddress(Module,'GetFilterPluginTable'); @Initialize:=GetProcAddress(Module,'InitializePlugin');
    @Uninitialize:=GetProcAddress(Module,'UninitializePlugin');
    Check(Assigned(GetTable) and Assigned(Initialize),'Missing production exports'); Check(Initialize(2011700)=1,'Host rejected');
    Table:=GetTable; Item:=PPointer(Table^.Items); Button:=nil;
    while Item^<>nil do begin if string(PItem(Item^)^.Name)='設定' then Button:=PFILTER_ITEM_BUTTON(Item^); Inc(Item) end;
    Check((Button<>nil) and Assigned(Button^.Callback2),'No settings callback');
    FillChar(Edit,SizeOf(Edit),0); Edit.SetObjectItemValue:=SetValue;
    TimerID:=SetTimer(0,0,300,@Tick); Check(TimerID<>0,'Cannot start DPI test timer');
    Button^.Callback2(@Edit,Pointer(1),'自動筆記','設定');
    Check(Failure='','DPI failure: '+Failure); Check(Stage=6,'DPI test did not finish');
    Writeln('ALL PASS: ',Checks,' DPI checks; actual monitor ',InitialDpi,' DPI');
  except on E: Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message); ExitCode:=1 end end;
  if TimerID<>0 then KillTimer(0,TimerID);
  if Module<>0 then begin if Assigned(Uninitialize) then Uninitialize; FreeLibrary(Module) end;
  SetThreadDpiAwarenessContext(PreviousContext);
end.
