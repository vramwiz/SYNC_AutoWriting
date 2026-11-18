unit AutoWriting_ReferenceData;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// 不変のフォント非依存データを二分探索する。戻り値の配列は呼出側所有。
// インク輪郭・ユーザー学習・ファイル・ネットワークは参照しない。
interface

uses System.Types;

type
  TReferenceStroke = record
    Points: TArray<TPointF>; // 正規化座標。配列の先頭から末尾が筆記方向。
    Curl: Boolean;
  end;
  TStrokeReference = record
    Codepoint, Source: Cardinal;
    Strokes: TArray<TReferenceStroke>;
  end;

function StrokeReferenceCount: Integer;
function StrokeReferenceCodepoint(Index: Integer): Cardinal;
function FindStrokeReference(Codepoint: Cardinal; out Reference: TStrokeReference): Boolean;

implementation

uses System.SysUtils;

const
  // このデータ部分だけCC BY-SA 3.0。Data/StrokeReference/NOTICE.mdを参照。
  Data: array[0..{$I '..\..\Data\StrokeReference\StrokeReferenceSize.inc'}] of Byte = (
{$I '..\..\Data\StrokeReference\StrokeReference.inc'}
  );

function U16(P: Integer): Cardinal; inline;
begin Result:=Cardinal(Data[P]) or (Cardinal(Data[P+1]) shl 8) end;
function U32(P: Integer): Cardinal; inline;
begin Result:=U16(P) or (U16(P+2) shl 16) end;
function StrokeReferenceCount: Integer;
begin Result:=U32(8) end;
function StrokeReferenceCodepoint(Index: Integer): Cardinal;
begin
  if (Index<0) or (Index>=StrokeReferenceCount) then raise EArgumentOutOfRangeException.Create('Reference index');
  Result:=U32(16+Index*16);
end;

function FindStrokeReference(Codepoint: Cardinal; out Reference: TStrokeReference): Boolean;
var Lo,Hi,M,P,E,I,J,N: Integer; Code: Cardinal;
begin
  Reference:=Default(TStrokeReference); Result:=False;
  Lo:=0; Hi:=StrokeReferenceCount-1;
  while Lo<=Hi do
  begin
    M:=(Lo+Hi) div 2; Code:=StrokeReferenceCodepoint(M);
    if Code<Codepoint then Lo:=M+1 else if Code>Codepoint then Hi:=M-1 else
    begin
      P:=U32(20+M*16); E:=P+Integer(U32(24+M*16));
      if (P<16+StrokeReferenceCount*16) or (E>Length(Data)) or (E<P+2) then Exit;
      Reference.Codepoint:=Codepoint; Reference.Source:=U32(28+M*16);
      N:=U16(P); Inc(P,2); if (N=0) or (N>64) then Exit;
      SetLength(Reference.Strokes,N);
      for I:=0 to N-1 do
      begin
        if P+4>E then Exit;
        Reference.Strokes[I].Curl:=U16(P)<>0; N:=U16(P+2); Inc(P,4);
        if (N<2) or (N>512) or (P+N*4>E) then Exit;
        SetLength(Reference.Strokes[I].Points,N);
        for J:=0 to N-1 do
        begin Reference.Strokes[I].Points[J]:=PointF(U16(P)/65535,U16(P+2)/65535); Inc(P,4) end;
      end;
      Result:=P=E; Exit;
    end;
  end;
end;

end.
