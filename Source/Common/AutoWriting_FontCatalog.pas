unit AutoWriting_FontCatalog;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// Windowsのインストール済みアウトライン書体名だけを列挙する。フォントデータは保存しない。
interface

uses System.Classes;

// Namesは呼出側所有。呼出中だけ借用し、重複・縦書き別名・ラスターフォントを除いて置換する。
procedure ListWritingFonts(Names: TStrings);

implementation

uses Winapi.Windows, System.SysUtils;

function CollectFont(const LF: TLogFont; const TM: TTextMetric; FontType: DWORD; Param: LPARAM): Integer; stdcall;
var Name: string;
begin
  Result:=1;
  if (FontType and TRUETYPE_FONTTYPE)=0 then Exit;
  try
    Name:=LF.lfFaceName;
    if (Name<>'') and (Name[1]<>'@') then TStrings(Param).Add(Name);
  except Result:=0 end;
end;

procedure ListWritingFonts(Names: TStrings);
var DC: HDC; LF: TLogFont; List: TStringList;
begin
  List:=TStringList.Create;
  try
    List.Sorted:=True; List.CaseSensitive:=False; List.Duplicates:=dupIgnore;
    DC:=CreateCompatibleDC(0); if DC=0 then RaiseLastOSError;
    try
      FillChar(LF,SizeOf(LF),0); LF.lfCharSet:=DEFAULT_CHARSET;
      EnumFontFamiliesEx(DC,LF,@CollectFont,LPARAM(List),0);
    finally DeleteDC(DC) end;
    Names.Assign(List);
  finally List.Free end;
end;

end.
