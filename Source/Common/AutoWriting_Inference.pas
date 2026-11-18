unit AutoWriting_Inference;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// グリッド化したフォント形状から中心線を推定する。日本語の正解筆順辞書ではない。
// 交差部は連続方向を優先し、元マスクの画素に筆記距離を割り当てる。

interface

uses AutoWriting_Types;

// Glyph所有のマスクを読み、推定経路・露出距離を更新する。ファイルは変更しない。
procedure InferGlyphStrokes(Glyph: TWritingGlyph; UseReference: Boolean=True);
// 学習データの並び替え・反転・経路修正後に距離と露出テーブルを再生成する。
procedure PrepareGlyphTiming(Glyph: TWritingGlyph);
procedure ReverseGlyphStroke(Glyph: TWritingGlyph; Index: Integer);
procedure MoveGlyphStroke(Glyph: TWritingGlyph; FromIndex, ToIndex: Integer);
// 選択点で画を分ける。結合は一覧で隣接する2画の点列をつなぐ。
function SplitGlyphStroke(Glyph: TWritingGlyph; StrokeIndex,PointIndex: Integer): Boolean;
function MergeGlyphStrokes(Glyph: TWritingGlyph; StrokeIndex: Integer): Boolean;

implementation

uses System.SysUtils, System.Types, System.Math, System.Generics.Collections, AutoWriting_Reveal, AutoWriting_Vertices,
  AutoWriting_ReferenceFit;

const
  DX: array[0..7] of Integer = (0,1,1,1,0,-1,-1,-1);
  DY: array[0..7] of Integer = (-1,-1,0,1,1,1,0,-1);

procedure InferGlyphStrokes(Glyph: TWritingGlyph; UseReference: Boolean);
var W,H,N,X,Y,I,J,K,Pass,Count,Transitions,Index,Cur,Prev,Next,Dir,BestDir: Integer;
  B,Remove,Visited: TBytes;
  Neighbours: array[0..7] of Integer;
  Changed,Allowed: Boolean;
  Paths: TList<TStroke>; Points: TList<TPointF>;
  S: TStroke; Score,BestScore,VX,VY,Len,Key1,Key2: Double; Temp: TStroke; ReferenceInfo: TReferenceFitInfo;
  function HasEdge(A,D: Integer): Boolean;
  var AX,AY,BX,BY: Integer;
  begin
    AX:=A mod W; AY:=A div W; BX:=AX+DX[D]; BY:=AY+DY[D];
    Result:=(BX>=0) and (BX<W) and (BY>=0) and (BY<H);
    if not Result then Exit;
    Result:=B[BY*W+BX]<>0;
    if Result and Odd(D) then
      Result:=(B[AY*W+BX]=0) and (B[BY*W+AX]=0);
  end;
  function Degree(A: Integer): Integer;
  var D: Integer;
  begin Result:=0; for D:=0 to 7 do if HasEdge(A,D) then Inc(Result) end;
  procedure Trace(Start: Integer);
  var D,CX,CY,TX,TY,Iteration: Integer;
  begin
    Cur:=Start; Prev:=-1; Points.Clear;
    for Iteration:=0 to N*4 do
    begin
      CX:=Cur mod W; CY:=Cur div W;
      Points.Add(PointF(CX-1,CY-1)); BestDir:=-1; BestScore:=-1E20;
      for D:=0 to 7 do
        if HasEdge(Cur,D) and ((Visited[Cur] and (1 shl D))=0) then
        begin
          Score:=-D*0.001;
          if Prev>=0 then
          begin
            TX:=Prev mod W; TY:=Prev div W;
            VX:=CX-TX; VY:=CY-TY;
            Score:=(VX*DX[D]+VY*DY[D])/Sqrt((VX*VX+VY*VY)*(DX[D]*DX[D]+DY[D]*DY[D]));
          end;
          if Score>BestScore then begin BestScore:=Score; BestDir:=D end;
        end;
      if BestDir<0 then Break;
      Next:=Cur+DY[BestDir]*W+DX[BestDir];
      Visited[Cur]:=Visited[Cur] or Byte(1 shl BestDir);
      Visited[Next]:=Visited[Next] or Byte(1 shl ((BestDir+4) mod 8));
      Prev:=Cur; Cur:=Next;
      if Cur=Start then begin Points.Add(Points[0]); Break end;
    end;
    if Points.Count<2 then Exit;
    S:=Default(TStroke); S.ID:=Paths.Count; S.Points:=Points.ToArray;
    Len:=0; for D:=1 to High(S.Points) do Len:=Len+Distance(S.Points[D-1],S.Points[D]);
    if Len<1.5 then Exit;
    // 左から右、上から下を初期方向とする。学習済みの方向は後から優先する。
    if (Abs(S.Points[0].X-S.Points[High(S.Points)].X)>
        Abs(S.Points[0].Y-S.Points[High(S.Points)].Y)) then
      Allowed:=S.Points[0].X>S.Points[High(S.Points)].X
    else Allowed:=S.Points[0].Y>S.Points[High(S.Points)].Y;
    if Allowed then
      for D:=0 to Length(S.Points) div 2-1 do
      begin
        VX:=S.Points[D].X; VY:=S.Points[D].Y;
        S.Points[D]:=S.Points[High(S.Points)-D];
        S.Points[High(S.Points)-D]:=PointF(VX,VY);
      end;
    Paths.Add(S);
  end;
begin
  Glyph.Strokes:=nil; Glyph.ReferenceUsed:=False; Glyph.ReferenceOrderOnly:=False;
  if (Glyph.Width=0) or (Glyph.Height=0) then begin PrepareGlyphTiming(Glyph); Exit end;
  W:=Glyph.Width+2; H:=Glyph.Height+2; N:=W*H;
  SetLength(B,N); SetLength(Remove,N); SetLength(Visited,N);
  for Y:=0 to Glyph.Height-1 do for X:=0 to Glyph.Width-1 do
    if Glyph.Mask[Y*Glyph.Width+X]>=64 then B[(Y+1)*W+X+1]:=1;
  // Zhang-Suenの2段階細線化。境界を残し、連結性を保って中心へ縮める。
  repeat
    Changed:=False;
    for Pass:=0 to 1 do
    begin
      FillChar(Remove[0],N,0);
      for Y:=1 to H-2 do for X:=1 to W-2 do
      begin
        Index:=Y*W+X; if B[Index]=0 then Continue;
        Count:=0; Transitions:=0;
        for I:=0 to 7 do begin Neighbours[I]:=B[Index+DY[I]*W+DX[I]]; Inc(Count,Neighbours[I]) end;
        if (Count<2) or (Count>6) then Continue;
        for I:=0 to 7 do if (Neighbours[I]=0) and (Neighbours[(I+1) mod 8]=1) then Inc(Transitions);
        if Transitions<>1 then Continue;
        if Pass=0 then Allowed:=(Neighbours[0]*Neighbours[2]*Neighbours[4]=0) and
          (Neighbours[2]*Neighbours[4]*Neighbours[6]=0)
        else Allowed:=(Neighbours[0]*Neighbours[2]*Neighbours[6]=0) and
          (Neighbours[0]*Neighbours[4]*Neighbours[6]=0);
        if Allowed then Remove[Index]:=1;
      end;
      for I:=0 to N-1 do if Remove[I]<>0 then begin B[I]:=0; Changed:=True end;
    end;
  until not Changed;
  Paths:=TList<TStroke>.Create; Points:=TList<TPointF>.Create;
  try
    for I:=0 to N-1 do if (B[I]<>0) and (Degree(I)=1) and (Visited[I]=0) then Trace(I);
    for I:=0 to N-1 do if B[I]<>0 then
    begin
      if Degree(I)=0 then
      begin
        S:=Default(TStroke); S.ID:=Paths.Count; SetLength(S.Points,2);
        S.Points[0]:=PointF(I mod W-1,I div W-1); S.Points[1]:=S.Points[0]; Paths.Add(S);
      end
      else for Dir:=0 to 7 do if HasEdge(I,Dir) and ((Visited[I] and (1 shl Dir))=0) then Trace(I);
    end;
    // 同じ上端帯では左から右へ。字形のみから筆順を完全には復元できない。
    for I:=1 to Paths.Count-1 do
    begin
      S:=Paths[I]; J:=I;
      Key1:=Floor(S.Points[0].Y/18)*AW_EM+S.Points[0].X;
      while J>0 do
      begin
        Temp:=Paths[J-1]; Key2:=Floor(Temp.Points[0].Y/18)*AW_EM+Temp.Points[0].X;
        if Key2<=Key1 then Break;
        Paths[J]:=Temp; Dec(J);
      end;
      Paths[J]:=S;
    end;
    Glyph.Strokes:=Paths.ToArray;
    for K:=0 to High(Glyph.Strokes) do Glyph.Strokes[K].ID:=K;
  finally Points.Free; Paths.Free end;
  if UseReference then Glyph.ReferenceUsed:=TryApplyStrokeReference(Glyph,ReferenceInfo);
  PrepareGlyphTiming(Glyph);
end;

procedure PrepareGlyphTiming(Glyph: TWritingGlyph);
var I,J: Integer;
  Start,Travel: Double;
  A,Last: TPointF;
begin
  Start:=0; Last:=PointF(0,0);
  for I:=0 to High(Glyph.Strokes) do
  begin
    if Length(Glyph.Strokes[I].Points)=0 then Continue;
    A:=Glyph.Strokes[I].Points[0];
    if I>0 then Start:=Start+Distance(Last,A);
    Glyph.Strokes[I].StartDistance:=Start; Travel:=0;
    for J:=1 to High(Glyph.Strokes[I].Points) do
      Travel:=Travel+Distance(Glyph.Strokes[I].Points[J-1],Glyph.Strokes[I].Points[J]);
    Glyph.Strokes[I].Length:=Max(1,Travel); Start:=Start+Glyph.Strokes[I].Length;
    Last:=Glyph.Strokes[I].Points[High(Glyph.Strokes[I].Points)];
  end;
  Glyph.TotalDistance:=Start; BuildGlyphReveal(Glyph);
end;

procedure ReverseGlyphStroke(Glyph: TWritingGlyph; Index: Integer);
var I: Integer; P: TPointF;
begin
  if (Index<0) or (Index>=Length(Glyph.Strokes)) then Exit;
  with Glyph.Strokes[Index] do
  begin
    PinnedVertices:=ReversePinnedVertices(PinnedVertices,System.Length(Points));
    for I:=0 to System.Length(Points) div 2-1 do
    begin P:=Points[I]; Points[I]:=Points[High(Points)-I]; Points[High(Points)-I]:=P end;
    Reversed:=not Reversed;
  end;
  PrepareGlyphTiming(Glyph);
end;

procedure MoveGlyphStroke(Glyph: TWritingGlyph; FromIndex,ToIndex: Integer);
var S: TStroke; I: Integer;
begin
  if (FromIndex<0) or (ToIndex<0) or (FromIndex>=Length(Glyph.Strokes)) or (ToIndex>=Length(Glyph.Strokes)) then Exit;
  S:=Glyph.Strokes[FromIndex];
  if FromIndex<ToIndex then for I:=FromIndex to ToIndex-1 do Glyph.Strokes[I]:=Glyph.Strokes[I+1]
  else for I:=FromIndex downto ToIndex+1 do Glyph.Strokes[I]:=Glyph.Strokes[I-1];
  Glyph.Strokes[ToIndex]:=S; PrepareGlyphTiming(Glyph);
end;

function SplitGlyphStroke(Glyph: TWritingGlyph; StrokeIndex,PointIndex: Integer): Boolean;
var Paths: TArray<TStroke>; I,NextID: Integer; Source: TStroke;
begin
  Result:=False;
  if (StrokeIndex<0) or (StrokeIndex>=Length(Glyph.Strokes)) then Exit;
  Source:=Glyph.Strokes[StrokeIndex];
  if (PointIndex<=0) or (PointIndex>=High(Source.Points)) then Exit;
  NextID:=0; for I:=0 to High(Glyph.Strokes) do NextID:=Max(NextID,Glyph.Strokes[I].ID+1);
  SetLength(Paths,Length(Glyph.Strokes)+1);
  for I:=0 to StrokeIndex do Paths[I]:=Glyph.Strokes[I];
  Paths[StrokeIndex].Points:=Copy(Source.Points,0,PointIndex+1);
  Paths[StrokeIndex].PinnedVertices:=SlicePinnedVertices(Source.PinnedVertices,0,PointIndex);
  Paths[StrokeIndex+1]:=Source; Paths[StrokeIndex+1].ID:=NextID;
  Paths[StrokeIndex+1].Points:=Copy(Source.Points,PointIndex,Length(Source.Points)-PointIndex);
  Paths[StrokeIndex+1].PinnedVertices:=SlicePinnedVertices(Source.PinnedVertices,PointIndex,High(Source.Points));
  for I:=StrokeIndex+1 to High(Glyph.Strokes) do Paths[I+1]:=Glyph.Strokes[I];
  Glyph.Strokes:=Paths; PrepareGlyphTiming(Glyph); Result:=True;
end;

function MergeGlyphStrokes(Glyph: TWritingGlyph; StrokeIndex: Integer): Boolean;
var Paths: TArray<TStroke>; I,J,Offset,First: Integer; A,B: TArray<TPointF>;
begin
  Result:=False;
  if (StrokeIndex<0) or (StrokeIndex>=High(Glyph.Strokes)) then Exit;
  A:=Glyph.Strokes[StrokeIndex].Points; B:=Glyph.Strokes[StrokeIndex+1].Points;
  if (Length(A)=0) or (Length(B)=0) then Exit;
  First:=0; if Distance(A[High(A)],B[0])<0.001 then First:=1;
  SetLength(Paths,Length(Glyph.Strokes)-1);
  for I:=0 to StrokeIndex do Paths[I]:=Glyph.Strokes[I];
  Offset:=Length(A); SetLength(Paths[StrokeIndex].Points,Offset+Length(B)-First);
  Paths[StrokeIndex].PinnedVertices:=JoinPinnedVertices(Glyph.Strokes[StrokeIndex].PinnedVertices,
    Glyph.Strokes[StrokeIndex+1].PinnedVertices,Offset-First);
  for J:=0 to High(A) do Paths[StrokeIndex].Points[J]:=A[J];
  for J:=First to High(B) do Paths[StrokeIndex].Points[Offset+J-First]:=B[J];
  for I:=StrokeIndex+1 to High(Paths) do Paths[I]:=Glyph.Strokes[I+1];
  Glyph.Strokes:=Paths; PrepareGlyphTiming(Glyph); Result:=True;
end;

end.
