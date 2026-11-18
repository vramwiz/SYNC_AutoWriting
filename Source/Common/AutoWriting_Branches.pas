unit AutoWriting_Branches;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 途中へ接続する枝を検出し、主線の前後を滑らかに変形して枝先を通る1画へ整理する。

interface

uses System.Types, AutoWriting_Types;

type
  TStrokeBranch = record
    Segment: Integer;
    T,MainLength,BranchLength,Score: Double;
    Root,Tip: TPointF;
  end;

// 読取専用。端点結合・重複経路・長い曲線を除外し、短い枝が主線の内部へ接続する場合だけ返す。
function FindStrokeBranch(const Main,Branch: TStroke; out Attachment: TStrokeBranch): Boolean;
// Glyphの経路だけを置換する。元マスク・ファイルは変更しない。失敗時は元の経路を残す。
// 成功後の距離・露出表は呼出側が再計算する。主線のID・方向・両端と未選択画は保持する。
function AbsorbStrokeBranch(Glyph: TWritingGlyph; MainIndex,BranchIndex: Integer;
  const Attachment: TStrokeBranch; out ResultIndex: Integer): Boolean;

implementation

uses System.Math, AutoWriting_Vertices;

type
  TProjection = record
    Segment: Integer;
    T,Distance,Along: Double;
    P: TPointF;
  end;

function PathLength(const Stroke: TStroke): Double;
var I: Integer;
begin
  Result:=0;
  for I:=1 to High(Stroke.Points) do Result:=Result+Distance(Stroke.Points[I-1],Stroke.Points[I]);
end;

function PositionAt(const Stroke: TStroke; Travel: Double): TPointF;
var I: Integer; Len,T: Double;
begin
  Result:=Stroke.Points[High(Stroke.Points)];
  for I:=1 to High(Stroke.Points) do
  begin
    Len:=Distance(Stroke.Points[I-1],Stroke.Points[I]); if Len<1E-9 then Continue;
    if Travel>Len then begin Travel:=Travel-Len; Continue end;
    T:=EnsureRange(Travel/Len,0.0,1.0);
    Exit(PointF(Stroke.Points[I-1].X+(Stroke.Points[I].X-Stroke.Points[I-1].X)*T,
      Stroke.Points[I-1].Y+(Stroke.Points[I].Y-Stroke.Points[I-1].Y)*T));
  end;
end;

function Project(const Stroke: TStroke; const P: TPointF): TProjection;
var I: Integer; A,B,Q: TPointF; VX,VY,LenSq,T,D,Travel,Len: Double;
begin
  Result:=Default(TProjection); Result.Segment:=-1; Result.Distance:=1E30; Travel:=0;
  for I:=1 to High(Stroke.Points) do
  begin
    A:=Stroke.Points[I-1]; B:=Stroke.Points[I]; VX:=B.X-A.X; VY:=B.Y-A.Y;
    LenSq:=VX*VX+VY*VY; Len:=Sqrt(LenSq); T:=0;
    if LenSq>1E-12 then T:=EnsureRange(((P.X-A.X)*VX+(P.Y-A.Y)*VY)/LenSq,0.0,1.0);
    Q:=PointF(A.X+VX*T,A.Y+VY*T); D:=Distance(P,Q);
    if D<Result.Distance-1E-8 then
    begin Result.Segment:=I-1; Result.T:=T; Result.P:=Q; Result.Distance:=D; Result.Along:=Travel+Len*T end;
    Travel:=Travel+Len;
  end;
end;

function FindStrokeBranch(const Main,Branch: TStroke; out Attachment: TStrokeBranch): Boolean;
const JOIN_RADIUS=1.5;
var MainLength,BranchLength,Margin,RootTravel,Score: Double;
  Side: Integer; Root,Tip,Probe: TPointF; Hit,FreeHit,ProbeHit: TProjection;
begin
  Result:=False; Attachment:=Default(TStrokeBranch); Attachment.Score:=1E30;
  if (Length(Main.Points)<2) or (Length(Branch.Points)<2) then Exit;
  MainLength:=PathLength(Main); BranchLength:=PathLength(Branch);
  if (MainLength<4) or (BranchLength<1E-6) then Exit;
  // 長い画や曲線全体を枝先だけへ置き換えない。吸収するのは短い突起に限る。
  if BranchLength>MainLength*0.5 then Exit;
  if BranchLength>1.4*Distance(Branch.Points[0],Branch.Points[High(Branch.Points)]) then Exit;
  Margin:=Max(2.0,Min(6.0,BranchLength*0.25));
  for Side:=0 to 1 do
  begin
    Root:=Branch.Points[0]; Tip:=Branch.Points[High(Branch.Points)];
    if Side=1 then begin Root:=Tip; Tip:=Branch.Points[0] end;
    Hit:=Project(Main,Root);
    if (Hit.Segment<0) or (Hit.Distance>JOIN_RADIUS) or
      (Hit.Along<Margin) or (MainLength-Hit.Along<Margin) then Continue;
    FreeHit:=Project(Main,Tip); if FreeHit.Distance<=JOIN_RADIUS*1.5 then Continue;
    // 主線と重なる経路や、もう一方の端も接続する輪を枝として吸収しない。
    RootTravel:=Min(BranchLength*0.5,JOIN_RADIUS*2);
    if Side=1 then RootTravel:=BranchLength-RootTravel;
    Probe:=PositionAt(Branch,RootTravel); ProbeHit:=Project(Main,Probe);
    if ProbeHit.Distance<=Max(JOIN_RADIUS*0.5,Hit.Distance) then Continue;
    Score:=Hit.Distance+0.01*BranchLength/Max(1,MainLength);
    if Score>=Attachment.Score then Continue;
    Attachment.Segment:=Hit.Segment; Attachment.T:=Hit.T; Attachment.Root:=Hit.P; Attachment.Tip:=Tip;
    Attachment.MainLength:=MainLength; Attachment.BranchLength:=BranchLength; Attachment.Score:=Score;
    Result:=True;
  end;
end;

function Densify(var Stroke: TStroke; var Joint: Integer): Boolean;
var Counts,Map: TArray<Integer>; Points: TArray<TPointF>; Pins: TArray<Integer>;
  I,J,K,Count: Integer; Step,T: Double;
begin
  Result:=False; if Length(Stroke.Points)>8192 then Exit;
  SetLength(Counts,Length(Stroke.Points)); SetLength(Map,Length(Stroke.Points)); Step:=1;
  repeat
    Count:=1;
    for I:=1 to High(Stroke.Points) do
    begin Counts[I]:=Max(1,Ceil(Distance(Stroke.Points[I-1],Stroke.Points[I])/Step)); Inc(Count,Counts[I]) end;
    if Count<=8192 then Break;
    Step:=Step*1.5;
  until False;
  SetLength(Points,Count); Points[0]:=Stroke.Points[0]; K:=1;
  for I:=1 to High(Stroke.Points) do
  begin
    for J:=1 to Counts[I] do
    begin
      T:=J/Counts[I];
      Points[K]:=PointF(Stroke.Points[I-1].X+(Stroke.Points[I].X-Stroke.Points[I-1].X)*T,
        Stroke.Points[I-1].Y+(Stroke.Points[I].Y-Stroke.Points[I-1].Y)*T);
      Inc(K);
    end;
    Map[I]:=K-1;
  end;
  SetLength(Pins,Length(Stroke.PinnedVertices));
  for I:=0 to High(Pins) do Pins[I]:=Map[Stroke.PinnedVertices[I]];
  Joint:=Map[Joint]; Stroke.Points:=Points; Stroke.PinnedVertices:=Pins; Result:=True;
end;

function AbsorbStrokeBranch(Glyph: TWritingGlyph; MainIndex,BranchIndex: Integer;
  const Attachment: TStrokeBranch; out ResultIndex: Integer): Boolean;
var Main: TStroke; Arc: TArray<Double>; Paths: TArray<TStroke>;
  I,J,Joint,At: Integer; LeftSpan,RightSpan,Reach,FromJoint,T,Weight,DX,DY,X,Y: Double;
begin
  Result:=False; ResultIndex:=-1;
  if (Glyph=nil) or (MainIndex=BranchIndex) or (MainIndex<0) or (BranchIndex<0) or
    (MainIndex>=Length(Glyph.Strokes)) or (BranchIndex>=Length(Glyph.Strokes)) then Exit;
  Main:=Glyph.Strokes[MainIndex]; Main.Points:=Copy(Main.Points); Main.PinnedVertices:=Copy(Main.PinnedVertices);
  if not InsertPathVertex(Main,Attachment.Segment,Attachment.T,True,Joint) then Exit;
  if not Densify(Main,Joint) then Exit;
  SetLength(Arc,Length(Main.Points));
  for I:=1 to High(Arc) do Arc[I]:=Arc[I-1]+Distance(Main.Points[I-1],Main.Points[I]);
  Reach:=Max(4.0,2*Max(Attachment.BranchLength,Distance(Attachment.Root,Attachment.Tip)));
  LeftSpan:=Min(Reach,Arc[Joint]); RightSpan:=Min(Reach,Arc[High(Arc)]-Arc[Joint]);
  // 手動で固定した周囲の頂点と、主線の始点・終点は動かさない。
  for I in Main.PinnedVertices do
  begin
    FromJoint:=Arc[I]-Arc[Joint];
    if FromJoint< -1E-6 then LeftSpan:=Min(LeftSpan,-FromJoint)
    else if FromJoint>1E-6 then RightSpan:=Min(RightSpan,FromJoint);
  end;
  if (LeftSpan<1E-6) or (RightSpan<1E-6) then Exit;
  DX:=Attachment.Tip.X-Main.Points[Joint].X; DY:=Attachment.Tip.Y-Main.Points[Joint].Y;
  for I:=0 to High(Main.Points) do
  begin
    FromJoint:=Arc[I]-Arc[Joint];
    if FromJoint<0 then T:=1+FromJoint/LeftSpan else T:=1-FromJoint/RightSpan;
    if T<=0 then Continue;
    T:=Min(1.0,T); Weight:=T*T*(3-2*T);
    X:=Main.Points[I].X+DX*Weight; Y:=Main.Points[I].Y+DY*Weight;
    if Glyph.Width>0 then X:=EnsureRange(X,-32.0,Glyph.Width+32.0);
    if Glyph.Height>0 then Y:=EnsureRange(Y,-32.0,Glyph.Height+32.0);
    Main.Points[I]:=PointF(X,Y);
  end;
  Main.Points[Joint]:=Attachment.Tip;
  At:=Min(MainIndex,BranchIndex); SetLength(Paths,Length(Glyph.Strokes)-1); J:=0;
  for I:=0 to High(Glyph.Strokes) do
  begin
    if I=At then begin Paths[J]:=Main; ResultIndex:=J; Inc(J) end;
    if (I=MainIndex) or (I=BranchIndex) then Continue;
    Paths[J]:=Glyph.Strokes[I]; Inc(J);
  end;
  Glyph.Strokes:=Paths; Result:=True;
end;

end.
