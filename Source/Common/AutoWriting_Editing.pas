unit AutoWriting_Editing;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 経路線上の選択、任意位置の分割、端点を指定する結合、独立した履歴スナップショット。
// 形状マスク・フォント・ファイルは変更せず、経路と露出タイミングだけを更新する。

interface

uses System.Types, AutoWriting_Types;

type
  TStrokeHit = record
    Stroke, Segment: Integer;
    T, Distance: Double;
    Point: TPointF;
    AtStart: Boolean;
  end;
  TGlyphEditState = record
    Strokes: TArray<TStroke>;
    Learned: Boolean;
  end;

// 座標と許容距離はマスクと同じ128 em単位。重なりは選択中の画を優先する。
function HitStroke(Glyph: TWritingGlyph; const Point: TPointF;
  MaxDistance: Double; PreferredStroke: Integer): TStrokeHit;
function HitEndpoint(Glyph: TWritingGlyph; const Point: TPointF;
  MaxDistance: Double; PreferredStroke: Integer; ExcludedStroke: Integer=-1): TStrokeHit;
// 点列の節点が存在しない位置も、補間点を挿入して分ける。端点そのものでは分けない。
function SplitStrokeAt(Glyph: TWritingGlyph; const Hit: TStrokeHit): Boolean;
// 選択した端点どうしを結ぶよう自動的に方向をそろえる。一覧で隣接していなくてもよい。
function JoinStrokeEndpoints(Glyph: TWritingGlyph; A: Integer; AStart: Boolean;
  B: Integer; BStart: Boolean; out ResultIndex: Integer): Boolean;
// 選択した行を順序どおりに結合する。接続距離が短くなる端点の向きを自動選択する。
function JoinSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
  out ResultIndex: Integer): Boolean;
// InsertIndexは元の一覧の行間0..Count。複数行を元の順序でまとめて挿入する。
function MoveSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
  InsertIndex: Integer; var NewIndices: TArray<Integer>): Boolean;
function ShiftSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
  Delta: Integer; var NewIndices: TArray<Integer>): Boolean;
// 履歴と実データの点列は独立して所有し、片方の編集がもう片方へ伝わらない。
function CaptureGlyphState(Glyph: TWritingGlyph): TGlyphEditState;
procedure RestoreGlyphState(Glyph: TWritingGlyph; const State: TGlyphEditState);

implementation

uses System.SysUtils, System.Math, AutoWriting_Inference;

function CloneStrokes(const Strokes: TArray<TStroke>): TArray<TStroke>;
var I: Integer;
begin
  Result:=Copy(Strokes);
  for I:=0 to High(Result) do Result[I].Points:=Copy(Strokes[I].Points);
end;

function CaptureGlyphState(Glyph: TWritingGlyph): TGlyphEditState;
begin Result.Strokes:=CloneStrokes(Glyph.Strokes); Result.Learned:=Glyph.Learned end;

procedure RestoreGlyphState(Glyph: TWritingGlyph; const State: TGlyphEditState);
begin
  Glyph.Strokes:=CloneStrokes(State.Strokes); Glyph.Learned:=State.Learned;
  PrepareGlyphTiming(Glyph);
end;

function EmptyHit(MaxDistance: Double): TStrokeHit;
begin
  Result:=Default(TStrokeHit); Result.Stroke:=-1; Result.Segment:=-1;
  Result.Distance:=MaxDistance;
end;

function HitStroke(Glyph: TWritingGlyph; const Point: TPointF;
  MaxDistance: Double; PreferredStroke: Integer): TStrokeHit;
var Pass,I,J: Integer; A,B,P: TPointF; VX,VY,LengthSq,T,D: Double;
begin
  Result:=EmptyHit(MaxDistance); if Glyph=nil then Exit;
  for Pass:=-1 to High(Glyph.Strokes) do
  begin
    I:=Pass;
    if Pass=-1 then I:=PreferredStroke else if I=PreferredStroke then Continue;
    if (I<0) or (I>=Length(Glyph.Strokes)) then Continue;
    for J:=0 to High(Glyph.Strokes[I].Points)-1 do
    begin
      A:=Glyph.Strokes[I].Points[J]; B:=Glyph.Strokes[I].Points[J+1];
      VX:=B.X-A.X; VY:=B.Y-A.Y; LengthSq:=VX*VX+VY*VY; T:=0;
      if LengthSq>1E-12 then T:=EnsureRange(((Point.X-A.X)*VX+(Point.Y-A.Y)*VY)/LengthSq,0.0,1.0);
      P:=PointF(A.X+VX*T,A.Y+VY*T); D:=Distance(Point,P);
      if D>Result.Distance+1E-6 then Continue;
      if (Result.Stroke>=0) and (D>=Result.Distance-1E-6) then Continue;
      Result.Stroke:=I; Result.Segment:=J; Result.T:=T; Result.Point:=P; Result.Distance:=D;
    end;
    if (Pass=-1) and (Result.Stroke>=0) then Exit;
  end;
end;

function HitEndpoint(Glyph: TWritingGlyph; const Point: TPointF;
  MaxDistance: Double; PreferredStroke: Integer; ExcludedStroke: Integer): TStrokeHit;
var Pass,I,J,Index: Integer; P: TPointF; D: Double;
begin
  Result:=EmptyHit(MaxDistance); if Glyph=nil then Exit;
  for Pass:=-1 to High(Glyph.Strokes) do
  begin
    I:=Pass;
    if Pass=-1 then I:=PreferredStroke else if I=PreferredStroke then Continue;
    if I=ExcludedStroke then Continue;
    if (I<0) or (I>=Length(Glyph.Strokes)) or (Length(Glyph.Strokes[I].Points)=0) then Continue;
    for J:=0 to 1 do
    begin
      Index:=0; if J=1 then Index:=High(Glyph.Strokes[I].Points);
      P:=Glyph.Strokes[I].Points[Index]; D:=Distance(Point,P);
      if D>Result.Distance+1E-6 then Continue;
      if (Result.Stroke>=0) and (D>=Result.Distance-1E-6) then Continue;
      Result.Stroke:=I; Result.AtStart:=J=0; Result.Point:=P; Result.Distance:=D;
    end;
    if (Pass=-1) and (Result.Stroke>=0) then Exit;
  end;
end;

function SplitStrokeAt(Glyph: TWritingGlyph; const Hit: TStrokeHit): Boolean;
var Points: TArray<TPointF>; I,Index: Integer; P: TPointF;
begin
  Result:=False;
  if (Glyph=nil) or (Hit.Stroke<0) or (Hit.Stroke>=Length(Glyph.Strokes)) then Exit;
  Points:=Glyph.Strokes[Hit.Stroke].Points;
  if (Hit.Segment<0) or (Hit.Segment>=High(Points)) or IsNan(Hit.T) or IsInfinite(Hit.T) then Exit;
  if Hit.T<=0.001 then Exit(SplitGlyphStroke(Glyph,Hit.Stroke,Hit.Segment));
  if Hit.T>=0.999 then Exit(SplitGlyphStroke(Glyph,Hit.Stroke,Hit.Segment+1));
  Index:=Hit.Segment+1;
  P:=PointF(Points[Index-1].X+(Points[Index].X-Points[Index-1].X)*Hit.T,
    Points[Index-1].Y+(Points[Index].Y-Points[Index-1].Y)*Hit.T);
  SetLength(Glyph.Strokes[Hit.Stroke].Points,Length(Points)+1);
  for I:=0 to Index-1 do Glyph.Strokes[Hit.Stroke].Points[I]:=Points[I];
  Glyph.Strokes[Hit.Stroke].Points[Index]:=P;
  for I:=Index to High(Points) do Glyph.Strokes[Hit.Stroke].Points[I+1]:=Points[I];
  Result:=SplitGlyphStroke(Glyph,Hit.Stroke,Index);
end;

function JoinStrokeEndpoints(Glyph: TWritingGlyph; A: Integer; AStart: Boolean;
  B: Integer; BStart: Boolean; out ResultIndex: Integer): Boolean;
var PA,PB: TArray<TPointF>; Paths: TArray<TStroke>; Joined: TStroke;
  I,J,First,Offset: Integer;
  function Oriented(const Points: TArray<TPointF>; Reverse: Boolean): TArray<TPointF>;
  var K: Integer;
  begin
    Result:=Copy(Points);
    if Reverse then for K:=0 to High(Points) do Result[K]:=Points[High(Points)-K];
  end;
begin
  Result:=False; ResultIndex:=-1;
  if (Glyph=nil) or (A<0) or (B<0) or (A=B) or (A>=Length(Glyph.Strokes)) or (B>=Length(Glyph.Strokes)) then Exit;
  PA:=Oriented(Glyph.Strokes[A].Points,AStart); PB:=Oriented(Glyph.Strokes[B].Points,not BStart);
  if (Length(PA)=0) or (Length(PB)=0) then Exit;
  Joined:=Glyph.Strokes[A]; Joined.Reversed:=Joined.Reversed xor AStart;
  First:=0; if Distance(PA[High(PA)],PB[0])<0.001 then First:=1;
  Offset:=Length(PA); SetLength(Joined.Points,Offset+Length(PB)-First);
  for I:=0 to High(PA) do Joined.Points[I]:=PA[I];
  for I:=First to High(PB) do Joined.Points[Offset+I-First]:=PB[I];
  SetLength(Paths,Length(Glyph.Strokes)-1); J:=0;
  for I:=0 to High(Glyph.Strokes) do
  begin
    if I=B then Continue;
    if I=A then begin Paths[J]:=Joined; ResultIndex:=J end else Paths[J]:=Glyph.Strokes[I];
    Inc(J);
  end;
  Glyph.Strokes:=Paths; PrepareGlyphTiming(Glyph); Result:=True;
end;

function SelectionMask(Count: Integer; const Indices: TArray<Integer>): TArray<Boolean>;
var I: Integer;
begin
  Result:=nil; if Length(Indices)=0 then Exit;
  SetLength(Result,Count);
  for I in Indices do
  begin
    if (I<0) or (I>=Count) then Exit(nil);
    if Result[I] then Exit(nil);
    Result[I]:=True;
  end;
end;

function MoveSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
  InsertIndex: Integer; var NewIndices: TArray<Integer>): Boolean;
var Selected: TArray<Boolean>; Order,Remaining: TArray<Integer>;
  I,J,At,Count: Integer; Paths: TArray<TStroke>; Selection: TArray<Integer>;
begin
  Selection:=Copy(Indices);
  Result:=False; NewIndices:=nil; if Glyph=nil then Exit;
  Count:=Length(Glyph.Strokes); if (Count=0) or (Length(Selection)=0) then Exit;
  Selected:=SelectionMask(Count,Selection);
  if Length(Selected)<>Count then Exit;
  InsertIndex:=EnsureRange(InsertIndex,0,Count); At:=InsertIndex;
  for I:=0 to InsertIndex-1 do if Selected[I] then Dec(At);
  SetLength(Remaining,Count-Length(Selection)); J:=0;
  for I:=0 to Count-1 do if not Selected[I] then begin Remaining[J]:=I; Inc(J) end;
  SetLength(Order,Count); J:=0;
  for I:=0 to At-1 do begin Order[J]:=Remaining[I]; Inc(J) end;
  SetLength(NewIndices,Length(Selection));
  for I:=0 to Count-1 do if Selected[I] then
  begin Order[J]:=I; NewIndices[J-At]:=J; Inc(J) end;
  for I:=At to High(Remaining) do begin Order[J]:=Remaining[I]; Inc(J) end;
  for I:=0 to Count-1 do if Order[I]<>I then begin Result:=True; Break end;
  if not Result then Exit;
  SetLength(Paths,Count); for I:=0 to Count-1 do Paths[I]:=Glyph.Strokes[Order[I]];
  Glyph.Strokes:=Paths; PrepareGlyphTiming(Glyph);
end;

function ShiftSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
  Delta: Integer; var NewIndices: TArray<Integer>): Boolean;
var Selected: TArray<Boolean>; I,J: Integer; S: TStroke; Selection: TArray<Integer>;
begin
  Selection:=Copy(Indices);
  Result:=False; NewIndices:=nil; if Glyph=nil then Exit;
  Selected:=SelectionMask(Length(Glyph.Strokes),Selection);
  if (Length(Selected)=0) or (Delta=0) then Exit;
  if Delta<0 then
  begin
    for I:=1 to High(Selected) do if Selected[I] and not Selected[I-1] then
    begin
      S:=Glyph.Strokes[I-1]; Glyph.Strokes[I-1]:=Glyph.Strokes[I]; Glyph.Strokes[I]:=S;
      Selected[I-1]:=True; Selected[I]:=False; Result:=True;
    end;
  end
  else for I:=High(Selected)-1 downto 0 do if Selected[I] and not Selected[I+1] then
  begin
    S:=Glyph.Strokes[I+1]; Glyph.Strokes[I+1]:=Glyph.Strokes[I]; Glyph.Strokes[I]:=S;
    Selected[I+1]:=True; Selected[I]:=False; Result:=True;
  end;
  SetLength(NewIndices,Length(Selection)); J:=0;
  for I:=0 to High(Selected) do if Selected[I] then begin NewIndices[J]:=I; Inc(J) end;
  if Result then PrepareGlyphTiming(Glyph);
end;

function JoinSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
  out ResultIndex: Integer): Boolean;
var Selected: TArray<Boolean>; First,Second,I,J,K,NextID: Integer;
  Work: TWritingGlyph; SelectedIDs: TArray<Integer>; AStart,BStart: Boolean;
  Cost,Best: Double; A,B: Integer;
begin
  Result:=False; ResultIndex:=-1;
  if (Glyph=nil) or (Length(Indices)<2) then Exit;
  Selected:=SelectionMask(Length(Glyph.Strokes),Indices); if Length(Selected)=0 then Exit;
  SetLength(SelectedIDs,Length(Indices)); J:=0;
  // 作業用の深い複製で結合し、失敗時には元の経路を残す。
  Work:=TWritingGlyph.Create;
  try
    Work.Strokes:=CloneStrokes(Glyph.Strokes);
    for I:=0 to High(Work.Strokes) do
    begin
      Work.Strokes[I].ID:=I;
      if Selected[I] then
      begin
        if Length(Work.Strokes[I].Points)=0 then Exit;
        SelectedIDs[J]:=I; Inc(J);
      end;
    end;
    First:=SelectedIDs[0]; Second:=SelectedIDs[1]; Best:=1E30; AStart:=False; BStart:=True;
    for A:=0 to 1 do for B:=0 to 1 do
    begin
      I:=0; if A=0 then I:=High(Work.Strokes[First].Points);
      K:=0; if B=0 then K:=High(Work.Strokes[Second].Points);
      if (I<0) or (K<0) then Exit;
      Cost:=Distance(Work.Strokes[First].Points[I],Work.Strokes[Second].Points[K]);
      if Cost<Best then begin Best:=Cost; AStart:=A=1; BStart:=B=1 end;
    end;
    if not JoinStrokeEndpoints(Work,First,AStart,Second,BStart,ResultIndex) then Exit;
    for J:=2 to High(SelectedIDs) do
    begin
      NextID:=SelectedIDs[J]; Second:=-1;
      for I:=0 to High(Work.Strokes) do if Work.Strokes[I].ID=NextID then begin Second:=I; Break end;
      if Second<0 then Exit;
      I:=High(Work.Strokes[ResultIndex].Points); K:=High(Work.Strokes[Second].Points);
      if (I<0) or (K<0) then Exit;
      BStart:=Distance(Work.Strokes[ResultIndex].Points[I],Work.Strokes[Second].Points[0])<=
        Distance(Work.Strokes[ResultIndex].Points[I],Work.Strokes[Second].Points[K]);
      if not JoinStrokeEndpoints(Work,ResultIndex,False,Second,BStart,ResultIndex) then Exit;
    end;
    for I:=0 to High(Work.Strokes) do Work.Strokes[I].ID:=Glyph.Strokes[Work.Strokes[I].ID].ID;
    Glyph.Strokes:=Work.Strokes; PrepareGlyphTiming(Glyph); Result:=True;
  finally Work.Free end;
end;

end.
