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
// 操作点と点のない線上を列挙する。別画の端点に重なる線も残し、線上のPointIndicesは-1。
function HitEditingPaths(Glyph: TWritingGlyph; const Point: TPointF; NodeRadius,LineRadius: Double;
  out PointIndices: TArray<Integer>): TArray<TStrokeHit>;
// 点列の節点が存在しない位置も、補間点を挿入して分ける。端点そのものでは分けない。
function SplitStrokeAt(Glyph: TWritingGlyph; const Hit: TStrokeHit): Boolean;
function CreateStrokeVertex(Glyph: TWritingGlyph; const Hit: TStrokeHit; out Index: Integer): Boolean;
// 選択した端点どうしを結ぶよう自動的に方向をそろえる。一覧で隣接していなくてもよい。
function JoinStrokeEndpoints(Glyph: TWritingGlyph; A: Integer; AStart: Boolean;
  B: Integer; BStart: Boolean; out ResultIndex: Integer): Boolean;
// 選択画の枝は主線へ吸収し、それ以外は一覧順に端点を結合する。原本は成功時だけ更新する。
function JoinSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
  out ResultIndex: Integer): Boolean;
// 選択画をまとめて除去する。未選択画の形とID・順序は保持し、全画削除も許可する。
function DeleteSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
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

uses System.SysUtils, System.Math, AutoWriting_Inference, AutoWriting_Vertices, AutoWriting_Branches;

function CloneStrokes(const Strokes: TArray<TStroke>): TArray<TStroke>;
var I: Integer;
begin
  Result:=Copy(Strokes);
  for I:=0 to High(Result) do
  begin Result[I].Points:=Copy(Strokes[I].Points); Result[I].PinnedVertices:=Copy(Strokes[I].PinnedVertices) end;
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

function HitEditingPaths(Glyph: TWritingGlyph; const Point: TPointF; NodeRadius,LineRadius: Double;
  out PointIndices: TArray<Integer>): TArray<TStrokeHit>;
var I,J,N,RunStart,RunEnd: Integer; Vertices: TArray<Integer>; H: TStrokeHit;
  A,B,P: TPointF; D,Best,VX,VY,LengthSq,T: Double;
  procedure AddHit(const Hit: TStrokeHit; Index: Integer);
  begin
    N:=Length(Result); SetLength(Result,N+1); SetLength(PointIndices,N+1);
    Result[N]:=Hit; PointIndices[N]:=Index;
  end;
  procedure FlushLine;
  var K: Integer; HasNode: Boolean;
  begin
    if H.Stroke>=0 then
    begin
      HasNode:=False;
      for K:=0 to High(Result) do if (Result[K].Stroke=I) and
        (PointIndices[K]>=RunStart) and (PointIndices[K]<=RunEnd+1) then begin HasNode:=True; Break end;
      if not HasNode then AddHit(H,-1);
    end;
    H.Stroke:=-1; Best:=LineRadius; RunStart:=-1; RunEnd:=-1;
  end;
begin
  Result:=nil; PointIndices:=nil; if Glyph=nil then Exit;
  for I:=0 to High(Glyph.Strokes) do
  begin
    Vertices:=EditingVertices(Glyph.Strokes[I]);
    for J in Vertices do
    begin
      P:=Glyph.Strokes[I].Points[J]; D:=Distance(Point,P); if D>NodeRadius then Continue;
      H:=Default(TStrokeHit); H.Stroke:=I; H.Point:=P; H.Distance:=D;
      H.Segment:=Max(0,J-1); H.T:=1; if J=0 then H.T:=0;
      AddHit(H,J);
    end;
  end;
  for I:=0 to High(Glyph.Strokes) do
  begin
    H.Stroke:=-1; Best:=LineRadius; RunStart:=-1; RunEnd:=-1;
    for J:=0 to High(Glyph.Strokes[I].Points)-1 do
    begin
      A:=Glyph.Strokes[I].Points[J]; B:=Glyph.Strokes[I].Points[J+1];
      VX:=B.X-A.X; VY:=B.Y-A.Y; LengthSq:=VX*VX+VY*VY; T:=0;
      if LengthSq>1E-12 then T:=EnsureRange(((Point.X-A.X)*VX+(Point.Y-A.Y)*VY)/LengthSq,0.0,1.0);
      P:=PointF(A.X+VX*T,A.Y+VY*T); D:=Distance(Point,P);
      if D>LineRadius then begin FlushLine; Continue end;
      if RunStart<0 then RunStart:=J; RunEnd:=J;
      if D>=Best then Continue;
      Best:=D; H:=Default(TStrokeHit); H.Stroke:=I; H.Segment:=J; H.T:=T; H.Point:=P; H.Distance:=D;
    end;
    FlushLine;
  end;
end;

function CreateStrokeVertex(Glyph: TWritingGlyph; const Hit: TStrokeHit; out Index: Integer): Boolean;
begin
  Result:=False; Index:=-1;
  if (Glyph=nil) or (Hit.Stroke<0) or (Hit.Stroke>=Length(Glyph.Strokes)) then Exit;
  Result:=InsertPathVertex(Glyph.Strokes[Hit.Stroke],Hit.Segment,Hit.T,True,Index);
  if Result then PrepareGlyphTiming(Glyph);
end;

function SplitStrokeAt(Glyph: TWritingGlyph; const Hit: TStrokeHit): Boolean;
var Index: Integer;
begin
  Result:=False;
  if (Glyph=nil) or (Hit.Stroke<0) or (Hit.Stroke>=Length(Glyph.Strokes)) then Exit;
  if not InsertPathVertex(Glyph.Strokes[Hit.Stroke],Hit.Segment,Hit.T,False,Index) then Exit;
  Result:=SplitGlyphStroke(Glyph,Hit.Stroke,Index);
end;

function JoinStrokeEndpoints(Glyph: TWritingGlyph; A: Integer; AStart: Boolean;
  B: Integer; BStart: Boolean; out ResultIndex: Integer): Boolean;
var PA,PB: TArray<TPointF>; VA,VB: TArray<Integer>; Paths: TArray<TStroke>; Joined: TStroke;
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
  VA:=Copy(Glyph.Strokes[A].PinnedVertices); VB:=Copy(Glyph.Strokes[B].PinnedVertices);
  if AStart then VA:=ReversePinnedVertices(VA,Length(PA));
  if not BStart then VB:=ReversePinnedVertices(VB,Length(PB));
  if (Length(PA)=0) or (Length(PB)=0) then Exit;
  Joined:=Glyph.Strokes[A]; Joined.Reversed:=Joined.Reversed xor AStart;
  First:=0; if Distance(PA[High(PA)],PB[0])<0.001 then First:=1;
  Offset:=Length(PA); SetLength(Joined.Points,Offset+Length(PB)-First);
  Joined.PinnedVertices:=JoinPinnedVertices(VA,VB,Offset-First);
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

function DeleteSelectedStrokes(Glyph: TWritingGlyph; const Indices: TArray<Integer>;
  out ResultIndex: Integer): Boolean;
var Selected: TArray<Boolean>; Paths: TArray<TStroke>; I,J,First: Integer;
begin
  Result:=False; ResultIndex:=-1;
  if Glyph=nil then Exit;
  Selected:=SelectionMask(Length(Glyph.Strokes),Indices);
  if (Length(Selected)=0) or (Length(Indices)=0) then Exit;
  SetLength(Paths,Length(Glyph.Strokes)-Length(Indices)); J:=0; First:=-1;
  for I:=0 to High(Glyph.Strokes) do
    if Selected[I] then begin if First<0 then First:=I end
    else begin Paths[J]:=Glyph.Strokes[I]; Inc(J) end;
  Glyph.Strokes:=Paths; ResultIndex:=Min(First,High(Paths)); PrepareGlyphTiming(Glyph); Result:=True;
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
var Selected: TArray<Boolean>; First,Second,I,J,K,RootID,RemovedID,MainID,Remaining: Integer;
  BestMain,BestBranch: Integer; Work: TWritingGlyph; AStart,BStart: Boolean;
  Cost,Best: Double; A,B: Integer; Candidate,Attachment: TStrokeBranch;
begin
  Result:=False; ResultIndex:=-1;
  if (Glyph=nil) or (Length(Indices)<2) then Exit;
  Selected:=SelectionMask(Length(Glyph.Strokes),Indices); if Length(Selected)=0 then Exit;
  // 作業用の深い複製で結合し、失敗時には元の経路を残す。
  Work:=TWritingGlyph.Create;
  try
    Work.Strokes:=CloneStrokes(Glyph.Strokes); Work.Width:=Glyph.Width; Work.Height:=Glyph.Height;
    for I:=0 to High(Work.Strokes) do
    begin
      Work.Strokes[I].ID:=I;
      if Selected[I] and (Length(Work.Strokes[I].Points)=0) then Exit;
    end;
    RootID:=-1; Remaining:=Length(Indices); Attachment:=Default(TStrokeBranch);
    while Remaining>1 do
    begin
      // 行順に枝どうしをつなぐ前に、選択全体から主線と枝の組を探す。
      BestMain:=-1; BestBranch:=-1; Best:=1E30;
      for I:=0 to High(Work.Strokes) do if Selected[Work.Strokes[I].ID] then
        for J:=0 to High(Work.Strokes) do if (I<>J) and Selected[Work.Strokes[J].ID] then
          if FindStrokeBranch(Work.Strokes[I],Work.Strokes[J],Candidate) and (Candidate.Score<Best) then
          begin Best:=Candidate.Score; BestMain:=I; BestBranch:=J; Attachment:=Candidate end;
      if BestMain>=0 then
      begin
        MainID:=Work.Strokes[BestMain].ID; RemovedID:=Work.Strokes[BestBranch].ID;
        if not AbsorbStrokeBranch(Work,BestMain,BestBranch,Attachment,ResultIndex) then Exit;
        Selected[RemovedID]:=False; if RootID=RemovedID then RootID:=MainID;
        Dec(Remaining); Continue;
      end;
      First:=-1; Second:=-1;
      for I:=0 to High(Work.Strokes) do if Selected[Work.Strokes[I].ID] then
        if (RootID<0) or (Work.Strokes[I].ID=RootID) then begin First:=I; Break end;
      for I:=0 to High(Work.Strokes) do if (I<>First) and Selected[Work.Strokes[I].ID] then begin Second:=I; Break end;
      if (First<0) or (Second<0) then Exit;
      AStart:=False; BStart:=True; Best:=1E30;
      if RootID<0 then
        for A:=0 to 1 do for B:=0 to 1 do
        begin
          I:=0; if A=0 then I:=High(Work.Strokes[First].Points);
          K:=0; if B=0 then K:=High(Work.Strokes[Second].Points);
          Cost:=Distance(Work.Strokes[First].Points[I],Work.Strokes[Second].Points[K]);
          if Cost<Best then begin Best:=Cost; AStart:=A=1; BStart:=B=1 end;
        end
      else begin
        I:=High(Work.Strokes[First].Points); K:=High(Work.Strokes[Second].Points);
        BStart:=Distance(Work.Strokes[First].Points[I],Work.Strokes[Second].Points[0])<=
          Distance(Work.Strokes[First].Points[I],Work.Strokes[Second].Points[K]);
      end;
      RemovedID:=Work.Strokes[Second].ID;
      if not JoinStrokeEndpoints(Work,First,AStart,Second,BStart,ResultIndex) then Exit;
      Selected[RemovedID]:=False; RootID:=Work.Strokes[ResultIndex].ID; Dec(Remaining);
    end;
    for I:=0 to High(Work.Strokes) do if Selected[Work.Strokes[I].ID] then begin ResultIndex:=I; Break end;
    for I:=0 to High(Work.Strokes) do Work.Strokes[I].ID:=Glyph.Strokes[Work.Strokes[I].ID].ID;
    Glyph.Strokes:=Work.Strokes; PrepareGlyphTiming(Glyph); Result:=True;
  finally Work.Free end;
end;

end.
