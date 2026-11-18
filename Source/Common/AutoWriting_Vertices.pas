unit AutoWriting_Vertices;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 描画用の細かな経路を残し、形状上必要な操作点とユーザーが追加した操作点だけを扱う。

interface

uses System.Types, AutoWriting_Types;

// 戻り値はPointsの添字。元経路は変更せず、直線の中間点を省き、折れ・曲線・固定点を残す。
function EditingVertices(const Stroke: TStroke): TArray<Integer>;
// 線分上の位置を節点にし、必要なら固定点として記録する。既存の節点は再利用する。
function InsertPathVertex(var Stroke: TStroke; Segment: Integer; T: Double;
  Pin: Boolean; out Index: Integer): Boolean;
// Originalは借用。周囲の操作点までの点列を連続的に変形し、Strokeへ独立した複製を返す。
function MovePathVertex(const Original: TStroke; Index: Integer; const Position: TPointF;
  var Stroke: TStroke): Boolean;
function SlicePinnedVertices(const Vertices: TArray<Integer>; First,Last: Integer): TArray<Integer>;
function ReversePinnedVertices(const Vertices: TArray<Integer>; PointCount: Integer): TArray<Integer>;
function JoinPinnedVertices(const A,B: TArray<Integer>; BOffset: Integer): TArray<Integer>;

implementation

uses System.Math, System.SysUtils, System.Generics.Collections;

function EditingVertices(const Stroke: TStroke): TArray<Integer>;
const TOLERANCE_SQ=0.75*0.75;
var Keep: TArray<Boolean>; Stack: TList<TPoint>; Range: TPoint;
  I,J,First,Last,Best,Count: Integer; A,B,P: TPointF; VX,VY,LengthSq,T,D,Maximum: Double;
begin
  Result:=nil; Count:=Length(Stroke.Points); if Count=0 then Exit;
  SetLength(Keep,Count); Keep[0]:=True; Keep[Count-1]:=True;
  for I in Stroke.PinnedVertices do if (I>=0) and (I<Count) then Keep[I]:=True;
  Stack:=TList<TPoint>.Create;
  try
    First:=0;
    for I:=1 to Count-1 do if Keep[I] then begin Stack.Add(Point(First,I)); First:=I end;
    while Stack.Count>0 do
    begin
      Range:=Stack.Last; Stack.Delete(Stack.Count-1); First:=Range.X; Last:=Range.Y;
      A:=Stroke.Points[First]; B:=Stroke.Points[Last]; VX:=B.X-A.X; VY:=B.Y-A.Y;
      LengthSq:=VX*VX+VY*VY; Best:=-1; Maximum:=TOLERANCE_SQ;
      for I:=First+1 to Last-1 do
      begin
        P:=Stroke.Points[I]; T:=0;
        if LengthSq>1E-12 then T:=EnsureRange(((P.X-A.X)*VX+(P.Y-A.Y)*VY)/LengthSq,0.0,1.0);
        D:=Sqr(P.X-A.X-VX*T)+Sqr(P.Y-A.Y-VY*T);
        if D>Maximum then begin Maximum:=D; Best:=I end;
      end;
      if Best>=0 then
      begin Keep[Best]:=True; Stack.Add(Point(First,Best)); Stack.Add(Point(Best,Last)) end;
    end;
    SetLength(Result,Count); J:=0;
    for I:=0 to Count-1 do if Keep[I] then begin Result[J]:=I; Inc(J) end;
    SetLength(Result,J);
  finally Stack.Free end;
end;

function SlicePinnedVertices(const Vertices: TArray<Integer>; First,Last: Integer): TArray<Integer>;
var I,N: Integer;
begin
  SetLength(Result,Length(Vertices)); N:=0;
  for I in Vertices do if (I>=First) and (I<=Last) then begin Result[N]:=I-First; Inc(N) end;
  SetLength(Result,N);
end;

function ReversePinnedVertices(const Vertices: TArray<Integer>; PointCount: Integer): TArray<Integer>;
var I: Integer;
begin
  SetLength(Result,Length(Vertices));
  for I:=0 to High(Vertices) do Result[I]:=PointCount-1-Vertices[High(Vertices)-I];
end;

function JoinPinnedVertices(const A,B: TArray<Integer>; BOffset: Integer): TArray<Integer>;
var I,N,Value: Integer;
begin
  SetLength(Result,Length(A)+Length(B)); N:=0;
  for I in A do begin Result[N]:=I; Inc(N) end;
  for I in B do
  begin
    Value:=I+BOffset;
    if (N>0) and (Result[N-1]>=Value) then Continue;
    Result[N]:=Value; Inc(N);
  end;
  SetLength(Result,N);
end;

function InsertPathVertex(var Stroke: TStroke; Segment: Integer; T: Double;
  Pin: Boolean; out Index: Integer): Boolean;
var Points: TArray<TPointF>; Pins,NewPins: TArray<Integer>; I,N: Integer; P: TPointF;
begin
  Result:=False; Index:=-1;
  if (Segment<0) or (Segment>=High(Stroke.Points)) or IsNan(T) or IsInfinite(T) or (T<0) or (T>1) then Exit;
  if T<=1E-6 then Index:=Segment else if T>=1-1E-6 then Index:=Segment+1
  else begin
    if Length(Stroke.Points)>=8192 then Exit;
    Index:=Segment+1; Points:=Copy(Stroke.Points);
    P:=PointF(Points[Segment].X+(Points[Index].X-Points[Segment].X)*T,
      Points[Segment].Y+(Points[Index].Y-Points[Segment].Y)*T);
    SetLength(Stroke.Points,Length(Points)+1);
    for I:=0 to Index-1 do Stroke.Points[I]:=Points[I]; Stroke.Points[Index]:=P;
    for I:=Index to High(Points) do Stroke.Points[I+1]:=Points[I];
    Pins:=Copy(Stroke.PinnedVertices);
    for I:=0 to High(Pins) do if Pins[I]>=Index then Inc(Pins[I]);
    Stroke.PinnedVertices:=Pins;
  end;
  if Pin then
  begin
    Pins:=Stroke.PinnedVertices; SetLength(NewPins,Length(Pins)+1); N:=0;
    for I in Pins do if I<Index then begin NewPins[N]:=I; Inc(N) end;
    NewPins[N]:=Index; Inc(N);
    for I in Pins do if I>Index then begin NewPins[N]:=I; Inc(N) end;
    SetLength(NewPins,N); Stroke.PinnedVertices:=NewPins;
  end;
  Result:=True;
end;

function MovePathVertex(const Original: TStroke; Index: Integer; const Position: TPointF;
  var Stroke: TStroke): Boolean;
var Vertices: TArray<Integer>; I,First,Last: Integer;
  Travel,LeftLength,RightLength,Weight,DX,DY: Double;
begin
  Result:=False; if (Index<0) or (Index>=Length(Original.Points)) then Exit;
  Vertices:=EditingVertices(Original); First:=0; Last:=High(Original.Points);
  for I in Vertices do
    if I<Index then First:=I else if I>Index then begin Last:=I; Break end;
  LeftLength:=0; RightLength:=0;
  for I:=First+1 to Index do LeftLength:=LeftLength+Distance(Original.Points[I-1],Original.Points[I]);
  for I:=Index+1 to Last do RightLength:=RightLength+Distance(Original.Points[I-1],Original.Points[I]);
  Stroke:=Original; Stroke.Points:=Copy(Original.Points); Stroke.PinnedVertices:=Copy(Original.PinnedVertices);
  DX:=Position.X-Original.Points[Index].X; DY:=Position.Y-Original.Points[Index].Y; Travel:=0;
  for I:=First to Last do
  begin
    if I>First then Travel:=Travel+Distance(Original.Points[I-1],Original.Points[I]);
    if I=Index then Weight:=1
    else if I<Index then Weight:=Travel/Max(1E-9,LeftLength)
    else Weight:=1-(Travel-LeftLength)/Max(1E-9,RightLength);
    Stroke.Points[I]:=PointF(Original.Points[I].X+DX*Weight,Original.Points[I].Y+DY*Weight);
  end;
  Result:=True;
end;

end.
