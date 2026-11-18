unit AutoWriting_LayoutTests;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// 検査EXE自身が開いたフォームだけを操作する。HWNDとCheckは呼出中だけ借用する。
interface

uses Winapi.Windows, AutoWriting_PenTests;

procedure CheckWritingSettingsLayout(Form: HWND; Check: TPenCheck);

implementation

uses System.SysUtils, System.Types, Winapi.Messages;

type
  PControls = ^TControls;
  TControls = record
    FontBox,Scroll,Size,PenSize,Angle,Lift,LightX,LightY,Bold,Italic,PenBox,Colour: HWND;
    CheckCount: Integer;
  end;

function FindControl(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var ClassName,Text: array[0..127] of Char; C: PControls;
begin
  Result:=True;
  try
    C:=PControls(Param); GetClassName(Wnd,ClassName,Length(ClassName)); GetWindowText(Wnd,Text,Length(Text));
    if string(ClassName)='TScrollBox' then C.Scroll:=Wnd;
    if (string(ClassName)='TComboBox') and (SendMessage(Wnd,CB_GETCOUNT,0,0)>6) then C.FontBox:=Wnd;
    if (string(ClassName)='TComboBox') and (SendMessage(Wnd,CB_GETCOUNT,0,0)=6) then C.PenBox:=Wnd;
    if (string(ClassName)='TButton') and (string(Text)='文字色を選択') then C.Colour:=Wnd;
    if string(ClassName)='TNumberBox' then C.PenSize:=Wnd;
    if string(ClassName)='TSpinEdit' then
    begin
      if string(Text)='80' then C.Size:=Wnd;
      if string(Text)='35' then C.Angle:=Wnd;
      if string(Text)='16' then C.Lift:=Wnd;
      if string(Text)='-100' then C.LightX:=Wnd;
      if string(Text)='-140' then C.LightY:=Wnd;
    end;
    if string(ClassName)='TCheckBox' then
    begin Inc(C.CheckCount); if string(Text)='太字' then C.Bold:=Wnd; if string(Text)='斜体' then C.Italic:=Wnd end;
  except Result:=False end;
end;

procedure CheckWritingSettingsLayout(Form: HWND; Check: TPenCheck);
var C: TControls; R,A,B: TRect; P: TPoint; Before,After: TScrollInfo; Text: array[0..127] of Char;
  Index: Integer; Position: LPARAM;
  procedure SameRow(LeftControl,RightControl: HWND; const Name: string);
  begin
    Check((LeftControl<>0) and (RightControl<>0),Name+' controls exist');
    GetWindowRect(LeftControl,A); GetWindowRect(RightControl,B);
    Check((Abs(A.Top-B.Top)<=1) and (A.Right<B.Left),Name+' are side by side');
  end;
begin
  FillChar(C,SizeOf(C),0); EnumChildWindows(Form,@FindControl,LPARAM(@C));
  Check((C.FontBox<>0) and (C.Scroll<>0) and (C.Size<>0),'Font combo and settings scroll found');
  Check(C.CheckCount=2,'Only bold and italic checkboxes remain');
  Check((C.PenBox<>0) and (C.Colour<>0),'Pen selector and ink colour found');
  GetWindowRect(C.PenBox,A); GetWindowRect(C.Colour,B);
  Check((B.Top>=A.Bottom) and (B.Top-A.Bottom<A.Height),'Colour control moved directly below the pen selector');
  Check((GetWindowLong(C.FontBox,GWL_STYLE) and $3)=CBS_DROPDOWNLIST,'Font selector is a list combo');
  Index:=SendMessage(C.FontBox,CB_FINDSTRINGEXACT,WPARAM(-1),LPARAM(PChar('ＭＳ ゴシック')));
  Check(Index>=0,'Font combo offers MS Gothic'); SendMessage(C.FontBox,CB_SETCURSEL,Index,0);
  SendMessage(GetParent(C.FontBox),WM_COMMAND,(GetDlgCtrlID(C.FontBox) and $FFFF) or (CBN_SELCHANGE shl 16),LPARAM(C.FontBox));
  Check((C.Bold<>0) and (C.Italic<>0),'Font styles remain available');
  SendMessage(C.Bold,BM_CLICK,0,0); SendMessage(C.Italic,BM_CLICK,0,0);
  SameRow(C.Size,C.PenSize,'Font and pen size'); SameRow(C.Angle,C.Lift,'Angle and lift'); SameRow(C.LightX,C.LightY,'Light XY');
  FillChar(Before,SizeOf(Before),0); Before.cbSize:=SizeOf(Before); Before.fMask:=SIF_ALL;
  Check(GetScrollInfo(C.Scroll,SB_VERT,Before),'Read settings scroll range');
  Check(Before.nMax>=Integer(Before.nPage),'Settings overflow is available for wheel test');
  GetWindowRect(Form,R); P:=Point(R.Right-80,R.Top+220);
  Position:=LPARAM((P.X and $FFFF) or ((P.Y and $FFFF) shl 16));
  SetFocus(C.Size); SendMessage(C.Size,WM_MOUSEWHEEL,WPARAM($FF880000),Position);
  After:=Before; GetScrollInfo(C.Scroll,SB_VERT,After);
  Check(After.nPos>Before.nPos,'Wheel scrolls over a focused parameter');
  GetWindowText(C.Size,Text,Length(Text)); Check(string(Text)='80','Scrolling does not alter the focused parameter');
  SendMessage(C.Size,WM_MOUSEWHEEL,WPARAM($00780000),Position);
  GetScrollInfo(C.Scroll,SB_VERT,After); Check(After.nPos=Before.nPos,'Wheel returns to original position');
end;

end.
