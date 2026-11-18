unit AutoWriting_Preview;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// UI専用の背景選択とDIB合成。動画用RGBAや字形・筆記時間を変更しない。
interface

uses AutoWriting_Types;

// RGB文字色に対して、コントラストの大きい白255または黒0を返す。
function PreviewBackground(InkColor: Cardinal): Byte;
// 設定欄のホイール量をスクロール位置へ変換する。Remainderは呼出側所有の高精度ホイール余り。
function SettingsWheelPosition(Current,Content,Viewport,Delta,Step: Integer; var Remainder: Integer): Integer;
// Pixelsは読取専用。Targetは呼出側所有のCount*4バイトBGRA領域を呼出中だけ借用する。
procedure CompositePreviewRow(const Pixels: TWritingPixels; Start,Count: Integer; Background: Byte; Target: PByte);

implementation

uses System.Math;

function SettingsWheelPosition(Current,Content,Viewport,Delta,Step: Integer; var Remainder: Integer): Integer;
var Movement,Limit: Integer;
begin
  Limit:=Max(0,Content-Viewport); Movement:=Delta*Step+Remainder;
  Result:=EnsureRange(Current-Movement div 120,0,Limit); Remainder:=Movement mod 120;
  if (Result=0) or (Result=Limit) then Remainder:=0;
end;

function PreviewBackground(InkColor: Cardinal): Byte;
var L: Double;
  function Linear(V: Cardinal): Double;
  begin
    Result:=V/255;
    if Result<=0.04045 then Result:=Result/12.92 else Result:=Power((Result+0.055)/1.055,2.4);
  end;
begin
  L:=0.2126*Linear((InkColor shr 16) and 255)+0.7152*Linear((InkColor shr 8) and 255)+0.0722*Linear(InkColor and 255);
  if 1.05/(L+0.05)>=(L+0.05)/0.05 then Result:=255 else Result:=0;
end;

procedure CompositePreviewRow(const Pixels: TWritingPixels; Start,Count: Integer; Background: Byte; Target: PByte);
var X,A,B: Integer;
begin
  for X:=0 to Count-1 do
  begin
    A:=Pixels[Start+X].A; B:=Background*(255-A)+127;
    Target[X*4]:=(Pixels[Start+X].B*A+B) div 255;
    Target[X*4+1]:=(Pixels[Start+X].G*A+B) div 255;
    Target[X*4+2]:=(Pixels[Start+X].R*A+B) div 255;
    Target[X*4+3]:=255;
  end;
end;

end.
