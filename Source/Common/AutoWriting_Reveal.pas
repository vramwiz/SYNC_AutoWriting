unit AutoWriting_Reveal;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 元字形を全経路から画別の転写領域へ分け、交差部だけ線幅を保った帯で共有する。
// 円形ブラシで周囲の未筆記画を拾わず、排他的な領域分割だけで生じる交差部の穴も補う。

interface

uses AutoWriting_Types;

// StartDistance/Length確定後に呼ぶ。Glyph所有のRevealだけを更新し、MaskとStrokesは変更しない。
// 領域分割・幅推定用の配列は呼出内だけで所有する。Mask=nilの幾何編集用コピーも可。
procedure BuildGlyphReveal(Glyph: TWritingGlyph);

implementation

uses System.SysUtils, System.Types, System.Math;

type
  TTransferSample = record
    P,Direction: TPointF;
    Travel,LeftWidth,RightWidth: Double;
  end;
  TTransferSamples = TArray<TTransferSample>;

function SampleStroke(const Stroke: TStroke): TTransferSamples;
var Cumulative: TArray<Double>; I,Count: Integer; Total,At: Double; A,B: TPointF;
  function Position(D: Double): TPointF;
  var L,R,M: Integer; T: Double;
  begin
    D:=EnsureRange(D,0.0,Total); L:=1; R:=High(Cumulative);
    while L<R do
    begin
      M:=(L+R) div 2; if Cumulative[M]<D then L:=M+1 else R:=M;
    end;
    T:=(D-Cumulative[L-1])/Max(1E-9,Cumulative[L]-Cumulative[L-1]);
    Result:=PointF(Stroke.Points[L-1].X+(Stroke.Points[L].X-Stroke.Points[L-1].X)*T,
      Stroke.Points[L-1].Y+(Stroke.Points[L].Y-Stroke.Points[L-1].Y)*T);
  end;
begin
  Result:=nil; if Length(Stroke.Points)=0 then Exit;
  SetLength(Cumulative,Length(Stroke.Points));
  for I:=1 to High(Cumulative) do Cumulative[I]:=Cumulative[I-1]+Distance(Stroke.Points[I-1],Stroke.Points[I]);
  Total:=Cumulative[High(Cumulative)];
  if Total<1E-6 then
  begin SetLength(Result,1); Result[0].P:=Stroke.Points[0]; Result[0].Direction:=PointF(1,0); Exit end;
  Count:=Max(2,Ceil(Total*2)+1); SetLength(Result,Count);
  for I:=0 to Count-1 do
  begin
    At:=Total*I/(Count-1); Result[I].P:=Position(At); Result[I].Travel:=At;
    // 細線化の1pxの階段を平滑化し、曲がりの前後に沿う接線を使う。
    A:=Position(At-3); B:=Position(At+3); At:=Distance(A,B);
    if At>1E-6 then Result[I].Direction:=PointF((B.X-A.X)/At,(B.Y-A.Y)/At)
    else Result[I].Direction:=PointF(1,0);
  end;
end;

procedure BuildGlyphReveal(Glyph: TWritingGlyph);
var W,H,N,I,J,X,Y,Index,Head,Tail,BestIndex: Integer;
  Queue,Depth: TArray<Integer>; SeedDistance,Transfer: TArray<Single>;
  Samples: TArray<TTransferSamples>;
  P,Direction,Normal: TPointF; D,Best,Exposure,U,V,Radius,LeftWidth,RightWidth: Double;
  X0,X1,Y0,Y1: Integer;
  function InkAt(const P: TPointF): Boolean;
  var X,Y: Integer;
  begin
    X:=Floor(P.X+0.5); Y:=Floor(P.Y+0.5);
    Result:=(X>=0) and (Y>=0) and (X<W) and (Y<H);
    if Result then Result:=Glyph.Mask[Y*W+X]>=32;
  end;
  function NormalWidth(const P,Normal: TPointF): Double;
  begin
    Result:=0; if not InkAt(P) then Exit;
    Result:=0.25;
    while (Result<AW_EM*0.3) and InkAt(PointF(P.X+Normal.X*Result,P.Y+Normal.Y*Result)) do
      Result:=Result+0.25;
    Result:=Max(0,Result-0.125);
  end;
  function StableWidth(const Path: TTransferSamples; At: Integer; Left: Boolean): Double;
  var Values: array[0..40] of Double; I,J,Count: Integer; Value: Double;
  begin
    Count:=0;
    for I:=Max(0,At-20) to Min(High(Path),At+20) do
    begin
      // 折れの別方向を混ぜない。交差部だけ突然広がる断面は近傍の通常幅で制限する。
      if Path[I].Direction.X*Path[At].Direction.X+Path[I].Direction.Y*Path[At].Direction.Y<0.92 then Continue;
      if Left then Value:=Path[I].LeftWidth else Value:=Path[I].RightWidth;
      if Value<=0 then Continue;
      J:=Count;
      while (J>0) and (Values[J-1]>Value) do begin Values[J]:=Values[J-1]; Dec(J) end;
      Values[J]:=Value; Inc(Count);
    end;
    Result:=0; if Count>0 then Result:=Values[Floor((Count-1)*0.3)]+0.25;
    if Left then Result:=Min(Result,Path[At].LeftWidth) else Result:=Min(Result,Path[At].RightWidth);
  end;
  procedure Spread(Pixel,Source: Integer);
  begin
    if (Glyph.Mask[Pixel]=0) or (Glyph.Reveal[Pixel]>=0) then Exit;
    Glyph.Reveal[Pixel]:=Glyph.Reveal[Source]; Queue[Tail]:=Pixel; Inc(Tail);
  end;
  procedure VisitOutline(Pixel,Source: Integer);
  begin
    if (Glyph.Mask[Pixel]=0) or (Depth[Pixel]>=0) then Exit;
    Depth[Pixel]:=Depth[Source]+1; Queue[Tail]:=Pixel; Inc(Tail);
  end;
  procedure TakeOutline(Pixel,Source: Integer);
  begin
    if Depth[Source]=Depth[Pixel]-1 then Transfer[Pixel]:=Max(Transfer[Pixel],Transfer[Source]);
  end;
begin
  N:=Length(Glyph.Mask); SetLength(Glyph.Reveal,N); if N=0 then Exit;
  W:=Glyph.Width; H:=Glyph.Height;
  if (W<=0) or (H<=0) or (Int64(W)*H<>N) then raise EArgumentException.Create('Invalid glyph mask');
  SetLength(Queue,N); SetLength(SeedDistance,N); SetLength(Transfer,N);
  SetLength(Samples,Length(Glyph.Strokes));
  for I:=0 to N-1 do begin Glyph.Reveal[I]:=-1; Transfer[I]:=-1; SeedDistance[I]:=1E20 end;
  // まず全画の中心線を同時に置く。未筆記画も領域を確保するため、隣の画へ漏れない。
  for I:=0 to High(Samples) do
  begin
    Samples[I]:=SampleStroke(Glyph.Strokes[I]);
    for J:=0 to High(Samples[I]) do
    begin
      P:=Samples[I][J].P; Direction:=Samples[I][J].Direction; Normal:=PointF(-Direction.Y,Direction.X);
      Samples[I][J].LeftWidth:=NormalWidth(P,Normal);
      Samples[I][J].RightWidth:=NormalWidth(P,PointF(-Normal.X,-Normal.Y));
      BestIndex:=-1; Best:=2.1;
      for Y:=Max(0,Round(P.Y)-1) to Min(H-1,Round(P.Y)+1) do
        for X:=Max(0,Round(P.X)-1) to Min(W-1,Round(P.X)+1) do
        begin
          Index:=Y*W+X; if Glyph.Mask[Index]=0 then Continue;
          D:=Sqr(X-P.X)+Sqr(Y-P.Y);
          if D<Best then begin Best:=D; BestIndex:=Index end;
        end;
      if BestIndex<0 then Continue;
      Exposure:=Glyph.Strokes[I].StartDistance+Samples[I][J].Travel;
      if (Best<SeedDistance[BestIndex]-1E-5) or
        ((Abs(Best-SeedDistance[BestIndex])<1E-5) and (Exposure<Glyph.Reveal[BestIndex])) then
      begin SeedDistance[BestIndex]:=Best; Glyph.Reveal[BestIndex]:=Exposure end;
    end;
  end;
  // 字形の中だけを成長させ、各画が転写する領域を分ける。空白を飛び越えて他の点を拾わない。
  Head:=0; Tail:=0;
  for I:=0 to N-1 do if Glyph.Reveal[I]>=0 then begin Queue[Tail]:=I; Inc(Tail) end;
  while Head<Tail do
  begin
    Index:=Queue[Head]; Inc(Head); X:=Index mod W; Y:=Index div W;
    if X>0 then Spread(Index-1,Index); if X<W-1 then Spread(Index+1,Index);
    if Y>0 then Spread(Index-W,Index); if Y<H-1 then Spread(Index+W,Index);
  end;
  for I:=0 to N-1 do if Glyph.Reveal[I]<0 then Glyph.Reveal[I]:=Max(0,Glyph.TotalDistance-0.1);
  // 交差の共有領域を、接線に垂直な細い断面として転写する。円形の膨張は行わない。
  // 周辺の安定した線幅を使うため、後続の縦画/横画が点状に先行表示されにくい。
  for I:=0 to High(Samples) do for J:=0 to High(Samples[I]) do
  begin
    if Length(Samples[I])=1 then Continue;
    P:=Samples[I][J].P; Direction:=Samples[I][J].Direction;
    Normal:=PointF(-Direction.Y,Direction.X);
    LeftWidth:=StableWidth(Samples[I],J,True); RightWidth:=StableWidth(Samples[I],J,False);
    Radius:=Max(LeftWidth,RightWidth)+1;
    X0:=Max(0,Floor(P.X-Radius)); X1:=Min(W-1,Ceil(P.X+Radius));
    Y0:=Max(0,Floor(P.Y-Radius)); Y1:=Min(H-1,Ceil(P.Y+Radius));
    for Y:=Y0 to Y1 do for X:=X0 to X1 do
    begin
      Index:=Y*W+X; if Glyph.Mask[Index]=0 then Continue;
      U:=(X-P.X)*Direction.X+(Y-P.Y)*Direction.Y;
      if Abs(U)>0.65 then Continue;
      V:=(X-P.X)*Normal.X+(Y-P.Y)*Normal.Y;
      if (V< -RightWidth) or (V>LeftWidth) then Continue;
      Exposure:=Glyph.Strokes[I].StartDistance+
        EnsureRange(Samples[I][J].Travel+U,0.0,Glyph.Strokes[I].Length);
      if (Transfer[Index]<0) or (Exposure<Transfer[Index]) then Transfer[Index]:=Exposure;
    end;
  end;
  // 帯の外のアンチエイリアス縁や飾りは、中心線でなく転写領域の端から補う。
  // 同距離の曖昧な縁は後の画を優先し、太い未筆記画の外縁に小さな点を残さない。
  SetLength(Depth,N); Head:=0; Tail:=0;
  for I:=0 to N-1 do
  begin
    Depth[I]:=-1;
    if Transfer[I]>=0 then begin Depth[I]:=0; Queue[Tail]:=I; Inc(Tail) end;
  end;
  while Head<Tail do
  begin
    Index:=Queue[Head]; Inc(Head); X:=Index mod W; Y:=Index div W;
    if X>0 then VisitOutline(Index-1,Index); if X<W-1 then VisitOutline(Index+1,Index);
    if Y>0 then VisitOutline(Index-W,Index); if Y<H-1 then VisitOutline(Index+W,Index);
  end;
  for I:=0 to Tail-1 do
  begin
    Index:=Queue[I]; if Depth[Index]=0 then Continue;
    X:=Index mod W; Y:=Index div W;
    if X>0 then TakeOutline(Index,Index-1); if X<W-1 then TakeOutline(Index,Index+1);
    if Y>0 then TakeOutline(Index,Index-W); if Y<H-1 then TakeOutline(Index,Index+W);
  end;
  // 通常幅の転写領域とその縁を優先する。単一点など帯を作れない成分だけ最初の分割を使う。
  for I:=0 to N-1 do if Transfer[I]>=0 then Glyph.Reveal[I]:=Transfer[I];
end;

end.
