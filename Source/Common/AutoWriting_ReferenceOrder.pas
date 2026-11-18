unit AutoWriting_ReferenceOrder;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// 全画の再構成が合わない書体では、元経路の点を保ち順序・方向だけ参照から補正する。
// 呼出側のGlyphとTargetsは呼出中だけ借用する。採用時だけStrokesを置換し、保存しない。
interface

uses System.Types, AutoWriting_Types;

function ApplyReferenceOrder(Glyph: TWritingGlyph; const Targets: TArray<TArray<TPointF>>;
  out Improvement: Double; out Reason: string): Boolean;

implementation

uses System.SysUtils, System.Math, AutoWriting_Vertices;

type
  TAssignment = record
    Original,Group: Integer;
    Progress,Span,Length,Error,Coverage: Double;
    Flip,Significant: Boolean;
  end;

function Nearest(const P: TPointF; const Line: TArray<TPointF>; out Progress: Double): Double;
var I: Integer; DX,DY,D,T,X,Y,Best,At,LengthBefore,Total,Segment: Double;
begin
  Total:=0; for I:=1 to High(Line) do Total:=Total+Distance(Line[I-1],Line[I]);
  Best:=1E30; At:=0; LengthBefore:=0;
  for I:=1 to High(Line) do
  begin
    DX:=Line[I].X-Line[I-1].X; DY:=Line[I].Y-Line[I-1].Y; D:=DX*DX+DY*DY;
    T:=0; if D>0.001 then T:=EnsureRange(((P.X-Line[I-1].X)*DX+(P.Y-Line[I-1].Y)*DY)/D,0.0,1.0);
    X:=Line[I-1].X+T*DX; Y:=Line[I-1].Y+T*DY; Segment:=Sqrt(D); D:=Sqr(P.X-X)+Sqr(P.Y-Y);
    if D<Best then begin Best:=D; At:=LengthBefore+Segment*T end;
    LengthBefore:=LengthBefore+Segment;
  end;
  Progress:=At/Max(0.001,Total); Result:=Sqrt(Best);
end;

function ApplyReferenceOrder(Glyph: TWritingGlyph; const Targets: TArray<TArray<TPointF>>;
  out Improvement: Double; out Reason: string): Boolean;
var Assigned,Sorted: TArray<TAssignment>; Paths: TArray<TStroke>; A,Swap: TAssignment;
  I,J,K,N,Index,Hits: Integer; P: TPointF; D,Best,Second,Progress,First,Last,Error,Delta,MaxD,Coverage,MaxLength: Double;
  Fractions: TArray<Double>; Changed,HasEvidence: Boolean;
begin
  Result:=False; Improvement:=0; Reason:='empty'; N:=Length(Glyph.Strokes); if (N=0) or (Length(Targets)=0) then Exit;
  // 各参照画が実フォント上に存在することを先に確認する。異なる字形を無理に対応させない。
  for I:=0 to High(Targets) do
  begin
    Error:=0; Hits:=0;
    for P in Targets[I] do
    begin
      Best:=1E30;
      for J:=0 to N-1 do Best:=Min(Best,Nearest(P,Glyph.Strokes[J].Points,Progress));
      Error:=Error+Best/Length(Targets[I]); if Best<=8 then Inc(Hits);
    end;
    Coverage:=Hits/Max(1,Length(Targets[I])); if (Error>5.5) or (Coverage<0.8) then
    begin Reason:=Format('target%d error=%.2f coverage=%.2f',[I,Error,Coverage]); Exit end;
  end;
  SetLength(Assigned,N); HasEvidence:=False; MaxLength:=0;
  for I:=0 to N-1 do
  begin
    D:=0; for J:=1 to High(Glyph.Strokes[I].Points) do D:=D+Distance(Glyph.Strokes[I].Points[J-1],Glyph.Strokes[I].Points[J]);
    MaxLength:=Max(MaxLength,D);
  end;
  for I:=0 to N-1 do
  begin
    A:=Default(TAssignment); A.Original:=I; A.Group:=-1;
    A.Length:=Glyph.Strokes[I].Length;
    if A.Length<=0 then for J:=1 to High(Glyph.Strokes[I].Points) do
      A.Length:=A.Length+Distance(Glyph.Strokes[I].Points[J-1],Glyph.Strokes[I].Points[J]);
    A.Significant:=A.Length>=Max(8,MaxLength*0.15); Best:=1E30; Second:=1E30;
    for K:=0 to High(Targets) do
    begin
      Error:=0; MaxD:=0; First:=0; Last:=0; Hits:=0; SetLength(Fractions,Length(Glyph.Strokes[I].Points));
      for J:=0 to High(Fractions) do
      begin
        D:=Nearest(Glyph.Strokes[I].Points[J],Targets[K],Progress); Fractions[J]:=Progress;
        Error:=Error+D/Length(Fractions); MaxD:=Max(MaxD,D); if D<=10 then Inc(Hits);
      end;
      // 端点の飾りに引きずられないよう、最初と最後の数点の投影位置を比較する。
      Index:=Min(4,Max(1,Length(Fractions) div 4)); if Length(Fractions)=0 then Exit;
      for J:=0 to Index-1 do begin First:=First+Fractions[J]/Index; Last:=Last+Fractions[High(Fractions)-J]/Index end;
      Delta:=Last-First;
      if Error<Best then
      begin
        Second:=Best; Best:=Error; A.Group:=K; A.Progress:=Min(First,Last); A.Span:=Abs(Delta);
        A.Flip:=Delta< -0.08; A.Error:=MaxD; A.Coverage:=Hits/Length(Fractions);
      end
      else Second:=Min(Second,Error);
    end;
    if (A.Group<0) or (Best>6) or (A.Coverage<0.8) then
    begin Reason:=Format('path%d error=%.2f max=%.2f',[I,Best,A.Error]); Exit end;
    if A.Significant and ((A.Span<0.08) or (Second-Best<0.8)) then
    begin Reason:=Format('path%d span=%.2f gap=%.2f length=%.2f',[I,A.Span,Second-Best,A.Length]); Exit end;
    if not A.Significant then A.Flip:=False;
    Assigned[I]:=A; HasEvidence:=HasEvidence or A.Significant;
  end;
  if not HasEvidence then Exit;
  Sorted:=Copy(Assigned);
  for I:=1 to N-1 do
  begin
    A:=Sorted[I]; J:=I;
    while J>0 do
    begin
      Swap:=Sorted[J-1];
      if (Swap.Group<A.Group) or ((Swap.Group=A.Group) and (Swap.Progress<=A.Progress)) then Break;
      Sorted[J]:=Swap; Dec(J);
    end;
    Sorted[J]:=A;
  end;
  Changed:=False;
  for I:=0 to N-1 do
  begin
    A:=Sorted[I]; if A.Significant and A.Flip then Improvement:=Improvement+A.Length;
    for J:=0 to I-1 do
      if A.Significant and Sorted[J].Significant and (Sorted[J].Original>A.Original) and
        ((Sorted[J].Group<A.Group) or ((Sorted[J].Group=A.Group) and (Sorted[J].Progress+0.08<A.Progress))) then
        Improvement:=Improvement+Min(A.Length,Sorted[J].Length);
    Changed:=Changed or (A.Original<>I) or A.Flip;
  end;
  if not Changed or (Improvement<8) then begin Reason:='unchanged'; Exit end;
  SetLength(Paths,N);
  for I:=0 to N-1 do
  begin
    A:=Sorted[I]; Paths[I]:=Glyph.Strokes[A.Original];
    if A.Flip then
    begin
      Paths[I].Points:=Copy(Paths[I].Points); Paths[I].Reversed:=not Paths[I].Reversed;
      Paths[I].PinnedVertices:=ReversePinnedVertices(Paths[I].PinnedVertices,Length(Paths[I].Points));
      for J:=0 to High(Paths[I].Points) do Paths[I].Points[J]:=Glyph.Strokes[A.Original].Points[High(Paths[I].Points)-J];
    end;
  end;
  Glyph.Strokes:=Paths; Reason:='accepted'; Result:=True;
end;

end.
