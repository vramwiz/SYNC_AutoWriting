unit AutoWriting_ReferenceFit;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// 参照経路をフォント中心線グラフへ照合する。参照座標を描画経路へコピーしない。
// Glyphを呼出中だけ借用し、採用時だけStrokesを置換する。Mask・学習・参照データは不変。
interface

uses AutoWriting_Types;

type
  TReferenceFitInfo = record
    Available, Accepted: Boolean;
    BeforeError, AfterError, Coverage: Double;
    RecoveredComponents: Integer;
    RepairedEdges: Integer;
    AdaptedGuide: Boolean;
    VariantIndex: Integer;
    OrderImprovement: Double;
    Reason,Mode,OrderReason: string;
  end;

function TryApplyStrokeReference(Glyph: TWritingGlyph; out Info: TReferenceFitInfo): Boolean;

implementation

uses System.SysUtils, System.Types, System.Math, System.Generics.Collections,
  AutoWriting_ReferenceData, AutoWriting_ReferenceOrder;

type
  TGraphNode = record
    P: TPointF;
    Count: Integer;
    Neighbours: array[0..7] of Integer;
  end;
  TNodes = TArray<TGraphNode>;
  TPoints = TArray<TPointF>;
  TPaths = TArray<TPoints>;
  TFoldAnchor = record
    Stage, Node: Integer;
  end;
  TFitStrategy = (fsBounds, fsAlign, fsRepair, fsAdapt, fsComponents, fsCompactComponents, fsFold, fsEndpoints,
    fsSerifs, fsSerifComponents);

function PathLength(const A: TPoints): Double;
var I: Integer;
begin Result:=0; for I:=1 to High(A) do Result:=Result+Distance(A[I-1],A[I]) end;

function TrimTerminalSerifs(const Path: TPoints; StartVertical, EndVertical: Boolean): TPoints;
const ProbeLength=6; MaxSerif=16;
var First, Last: Integer;
  function StemJunction(FromIndex, Direction: Integer; Vertical: Boolean): Integer;
  var I, At, Inner, Outer: Integer;
      Spread, Step: TPointF;
    function Orient(const P: TPointF): TPointF;
    begin
      if Vertical then Result:=P else Result:=PointF(P.Y,P.X);
    end;
  begin
    Result:=FromIndex;
    for I:=0 to MaxSerif do
    begin
      At:=FromIndex+Direction*I;
      Inner:=At+Direction*ProbeLength;
      if (Inner<0) or (Inner>High(Path)) then Exit;
      Spread:=Orient(Path[At]-Path[FromIndex]);
      if Abs(Spread.Y)>6 then Exit;
      Step:=Orient(Path[Inner]-Path[At]);
      if (Abs(Step.X)>3) or (Abs(Step.Y)<5) then Continue;
      if Abs(Spread.X)>=5 then
      begin
        Outer:=At;
        while (Outer<>FromIndex) and (Abs(Orient(Path[Outer-Direction]-Path[At]).X)<2) do Dec(Outer,Direction);
        Result:=Outer;
      end;
      Exit;
    end;
  end;
begin
  First:=StemJunction(0,1,StartVertical); Last:=StemJunction(High(Path),-1,EndVertical);
  if (Last-First<ProbeLength*2) or ((First=0) and (Last=High(Path))) then Exit(Path);
  Result:=Copy(Path,First,Last-First+1);
end;

function Samples(const A: TPoints; Count: Integer): TPoints;
var D: TArray<Double>; I,J: Integer; Target,F,Total: Double;
begin
  Result:=nil; if Length(A)<2 then Exit;
  SetLength(D,Length(A)); for I:=1 to High(A) do D[I]:=D[I-1]+Distance(A[I-1],A[I]);
  Total:=D[High(D)]; SetLength(Result,Count); J:=1;
  for I:=0 to Count-1 do
  begin
    Target:=Total*I/(Count-1);
    while (J<High(A)) and (D[J]<Target) do Inc(J);
    F:=0; if D[J]>D[J-1] then F:=(Target-D[J-1])/(D[J]-D[J-1]);
    Result[I]:=PointF(A[J-1].X+(A[J].X-A[J-1].X)*F,A[J-1].Y+(A[J].Y-A[J-1].Y)*F);
  end;
end;

function BuildGraph(G: TWritingGlyph; out Recovered: Integer): TNodes;
var Map,Queue: TArray<Integer>; Visited: TBytes; I,J,A,B,X,Y,K,Head,Tail,NX,NY,QX,QY,MinX,MinY,MaxX,MaxY: Integer;
  S: TStroke; List: TList<TGraphNode>; Node: TGraphNode; HasNode: Boolean; SumX,SumY,Best,D: Double;
  function Vertex(const P: TPointF): Integer;
  begin
    X:=Round(P.X); Y:=Round(P.Y);
    if (X<0) or (X>=G.Width) or (Y<0) or (Y>=G.Height) then Exit(-1);
    K:=Y*G.Width+X; Result:=Map[K];
    if Result<0 then
    begin Node:=Default(TGraphNode); Node.P:=PointF(X,Y); Result:=List.Count; Map[K]:=Result; List.Add(Node) end;
  end;
  procedure Edge(FromNode,ToNode: Integer);
  var V: TGraphNode; N: Integer;
  begin
    V:=List[FromNode];
    for N:=0 to V.Count-1 do if V.Neighbours[N]=ToNode then Exit;
    if V.Count>=8 then Exit;
    V.Neighbours[V.Count]:=ToNode; Inc(V.Count); List[FromNode]:=V;
  end;
begin
  Recovered:=0;
  SetLength(Map,G.Width*G.Height); for I:=0 to High(Map) do Map[I]:=-1;
  List:=TList<TGraphNode>.Create;
  try
    for S in G.Strokes do
    begin
      A:=-1;
      for J:=0 to High(S.Points) do
      begin
        B:=Vertex(S.Points[J]);
        if (A>=0) and (B>=0) and (A<>B) and (Distance(List[A].P,List[B].P)<1.5) then
        begin Edge(A,B); Edge(B,A) end;
        A:=B;
      end;
    end;
    // 従来の微小線除去で点が消えた成分だけ、実マスク内の重心近傍を復元する。
    // 大きな未対応成分や参照の座標からは節点を作らない。
    SetLength(Visited,Length(Map)); SetLength(Queue,Length(Map));
    for I:=0 to High(Map) do
    begin
      if (G.Mask[I]<64) or (Visited[I]<>0) then Continue;
      Head:=0; Tail:=1; Queue[0]:=I; Visited[I]:=1; HasNode:=False; SumX:=0; SumY:=0;
      MinX:=G.Width; MinY:=G.Height; MaxX:=0; MaxY:=0;
      while Head<Tail do
      begin
        K:=Queue[Head]; Inc(Head); QX:=K mod G.Width; QY:=K div G.Width;
        HasNode:=HasNode or (Map[K]>=0); SumX:=SumX+QX; SumY:=SumY+QY;
        MinX:=Min(MinX,QX); MinY:=Min(MinY,QY); MaxX:=Max(MaxX,QX); MaxY:=Max(MaxY,QY);
        for NY:=Max(0,QY-1) to Min(G.Height-1,QY+1) do for NX:=Max(0,QX-1) to Min(G.Width-1,QX+1) do
        begin
          J:=NY*G.Width+NX;
          if (G.Mask[J]>=64) and (Visited[J]=0) then begin Visited[J]:=1; Queue[Tail]:=J; Inc(Tail) end;
        end;
      end;
      if not HasNode then
      begin
        if (MaxX-MinX>20) or (MaxY-MinY>20) then Exit(nil);
        SumX:=SumX/Tail; SumY:=SumY/Tail; Best:=1E30; A:=Queue[0];
        for J:=0 to Tail-1 do
        begin K:=Queue[J]; D:=Sqr(K mod G.Width-SumX)+Sqr(K div G.Width-SumY); if D<Best then begin Best:=D; A:=K end end;
        Node:=Default(TGraphNode); Node.P:=PointF(A mod G.Width,A div G.Width); Map[A]:=List.Count; List.Add(Node); Inc(Recovered);
      end;
    end;
    Result:=List.ToArray;
  finally List.Free end;
end;

function RepairGraphNeighbours(Glyph: TWritingGlyph; var Nodes: TNodes): Integer;
var Map: TArray<Integer>; I,J,X,Y,NX,NY,K,D: Integer; Exists: Boolean;
begin
  Result:=0; SetLength(Map,Glyph.Width*Glyph.Height);
  for I:=0 to High(Map) do Map[I]:=-1;
  for I:=0 to High(Nodes) do Map[Round(Nodes[I].P.Y)*Glyph.Width+Round(Nodes[I].P.X)]:=I;
  // 微小線の除去で消えた辺だけを、隣接する既存の中心線節点から復元する。
  // 白い隙間や離れた画を接続せず、元の細線化と同じ斜め辺の条件を守る。
  for I:=0 to High(Nodes) do
  begin
    X:=Round(Nodes[I].P.X); Y:=Round(Nodes[I].P.Y);
    for NY:=Max(0,Y-1) to Min(Glyph.Height-1,Y+1) do
      for NX:=Max(0,X-1) to Min(Glyph.Width-1,X+1) do
      begin
        J:=Map[NY*Glyph.Width+NX]; if (J<0) or (J=I) then Continue;
        if (NX<>X) and (NY<>Y) and ((Map[Y*Glyph.Width+NX]>=0) or (Map[NY*Glyph.Width+X]>=0)) then Continue;
        Exists:=False;
        for D:=0 to Nodes[I].Count-1 do if Nodes[I].Neighbours[D]=J then begin Exists:=True; Break end;
        if Exists or (Nodes[I].Count>=8) then Continue;
        K:=Nodes[I].Count; Nodes[I].Neighbours[K]:=J; Inc(Nodes[I].Count); Inc(Result);
      end;
  end;
  Result:=Result div 2;
end;

function AlignReferenceComponents(const Nodes: TNodes; var Targets: TPaths;
  AllowNarrowMarks: Boolean; AllowPointMarks: Boolean = False): Boolean;
var Labels,Queue,Parents,Groups,RootGroups,Choices,Assigned: TArray<Integer>;
  RLo,RHi,NLo,NHi: TPoints; Costs: TArray<Double>; I,J,K,V,Head,Tail,NC,RC,A,B,Mask,Next,Stage: Integer;
  P,Q,RCenter,NCenter,Scale: TPointF; D,Best,DX,DY,MinimumScale: Double;
  function Root(Index: Integer): Integer;
  begin Result:=Index; while Parents[Result]<>Result do Result:=Parents[Result] end;
  procedure Bounds(var Lo,Hi: TPointF; const Point: TPointF);
  begin Lo.X:=Min(Lo.X,Point.X); Lo.Y:=Min(Lo.Y,Point.Y); Hi.X:=Max(Hi.X,Point.X); Hi.Y:=Max(Hi.Y,Point.Y) end;
begin
  Result:=False; NC:=0; RC:=0; SetLength(Labels,Length(Nodes)); SetLength(Queue,Length(Nodes));
  for I:=0 to High(Labels) do Labels[I]:=-1;
  for I:=0 to High(Nodes) do if Labels[I]<0 then
  begin
    Head:=0; Tail:=1; Queue[0]:=I; Labels[I]:=NC;
    while Head<Tail do
    begin
      K:=Queue[Head]; Inc(Head);
      for J:=0 to Nodes[K].Count-1 do
      begin V:=Nodes[K].Neighbours[J]; if Labels[V]<0 then begin Labels[V]:=NC; Queue[Tail]:=V; Inc(Tail) end end;
    end;
    Inc(NC);
  end;
  if (NC<2) or (NC>8) then Exit;
  SetLength(Parents,Length(Targets)); SetLength(Groups,Length(Targets)); SetLength(RootGroups,Length(Targets));
  for I:=0 to High(Parents) do begin Parents[I]:=I; RootGroups[I]:=-1 end;
  for I:=0 to High(Targets) do for J:=0 to I-1 do
  begin
    Best:=1E30;
    for P in Targets[I] do for Q in Targets[J] do Best:=Min(Best,Distance(P,Q));
    if Best<=2.5 then begin A:=Root(I); B:=Root(J); Parents[A]:=B end;
  end;
  for I:=0 to High(Targets) do
  begin K:=Root(I); if RootGroups[K]<0 then begin RootGroups[K]:=RC; Inc(RC) end; Groups[I]:=RootGroups[K] end;
  if RC<>NC then Exit;
  SetLength(RLo,RC); SetLength(RHi,RC); SetLength(NLo,NC); SetLength(NHi,NC);
  for I:=0 to RC-1 do begin RLo[I]:=PointF(1E9,1E9); RHi[I]:=PointF(-1E9,-1E9); NLo[I]:=RLo[I]; NHi[I]:=RHi[I] end;
  for I:=0 to High(Targets) do for P in Targets[I] do Bounds(RLo[Groups[I]],RHi[Groups[I]],P);
  for I:=0 to High(Nodes) do Bounds(NLo[Labels[I]],NHi[Labels[I]],Nodes[I].P);
  SetLength(Costs,1 shl RC); SetLength(Choices,Length(Costs));
  for I:=0 to High(Costs) do begin Costs[I]:=1E30; Choices[I]:=-1 end; Costs[0]:=0;
  for Mask:=0 to High(Costs)-1 do
  begin
    Stage:=0; K:=Mask; while K<>0 do begin Inc(Stage,K and 1); K:=K shr 1 end;
    if Stage>=RC then Continue;
    RCenter:=PointF((RLo[Stage].X+RHi[Stage].X)/2,(RLo[Stage].Y+RHi[Stage].Y)/2);
    for J:=0 to NC-1 do if (Mask and (1 shl J))=0 then
    begin
      NCenter:=PointF((NLo[J].X+NHi[J].X)/2,(NLo[J].Y+NHi[J].Y)/2);
      D:=Sqr(RCenter.X-NCenter.X)+Sqr(RCenter.Y-NCenter.Y); Next:=Mask or (1 shl J);
      if Costs[Mask]+D<Costs[Next] then begin Costs[Next]:=Costs[Mask]+D; Choices[Next]:=J end;
    end;
  end;
  SetLength(Assigned,RC); Mask:=High(Costs);
  for I:=RC-1 downto 0 do begin Assigned[I]:=Choices[Mask]; if Assigned[I]<0 then Exit; Mask:=Mask xor (1 shl Assigned[I]) end;
  for I:=0 to High(Targets) do
  begin
    A:=Groups[I]; B:=Assigned[A]; DX:=RHi[A].X-RLo[A].X; DY:=RHi[A].Y-RLo[A].Y;
    Scale:=PointF(1,1); if DX>0.001 then Scale.X:=(NHi[B].X-NLo[B].X)/DX;
    if DY>0.001 then Scale.Y:=(NHi[B].Y-NLo[B].Y)/DY;
    // 縦長の濁点など、離れた小さい要素では同じ位置でも横幅に字体差が出る。
    MinimumScale:=0.4;
    if AllowNarrowMarks and (Max(DX,DY)<=18) then MinimumScale:=0.3;
    if AllowPointMarks and (Max(DX,DY)<=4) and
      (Max(NHi[B].X-NLo[B].X,NHi[B].Y-NLo[B].Y)<=4) then Scale:=PointF(0,0)
    else if (Scale.X<MinimumScale) or (Scale.X>2.5) or (Scale.Y<MinimumScale) or (Scale.Y>2.5) then Exit;
    RCenter:=PointF((RLo[A].X+RHi[A].X)/2,(RLo[A].Y+RHi[A].Y)/2);
    NCenter:=PointF((NLo[B].X+NHi[B].X)/2,(NLo[B].Y+NHi[B].Y)/2);
    for J:=0 to High(Targets[I]) do Targets[I][J]:=PointF((Targets[I][J].X-RCenter.X)*Scale.X+NCenter.X,(Targets[I][J].Y-RCenter.Y)*Scale.Y+NCenter.Y);
  end;
  Result:=True;
end;

// 字体差による局所的な位置ずれを滑らかに補正する。これは探索用の案内線のみ。
// 開いた画の始終点は、参照の接続関係と進行方向に合う実フォントの端点へ対応させる。
function AdaptGuides(const Nodes: TNodes; var Targets: TPaths; EndpointsFirst: Boolean): Boolean;
var Original: TPaths; Offsets: TPoints; I,J,K,EndIndex,N,BestNode,V: Integer;
  P,Delta,Direction,Vector,Anchor: TPointF; Best,D,Len,Cosine,Score,F,Weight,OldLength: Double;
  Connected,Closed: Boolean;
  function Squared(const A,B: TPointF): Double;
  begin Result:=Sqr(A.X-B.X)+Sqr(A.Y-B.Y) end;
  function PullToCenterline: Boolean;
  var
    Pass, PointIndex, NodeIndex, NearestNode, Offset, Neighbour, FirstEditable: Integer;
    Point, Change: TPointF;
    Nearest, DistanceSquared, Blend: Double;
  begin
    FirstEditable := Ord(EndpointsFirst);
    for Pass := 0 to 1 do
    begin
      for PointIndex := 0 to N - 1 do
      begin
        Point := Targets[I][PointIndex];
        Nearest := 1E30;
        NearestNode := -1;
        for NodeIndex := 0 to High(Nodes) do
        begin
          DistanceSquared := Squared(Point, Nodes[NodeIndex].P);
          if DistanceSquared < Nearest then
          begin
            Nearest := DistanceSquared;
            NearestNode := NodeIndex;
          end;
        end;
        if (NearestNode < 0) or (Nearest > 400) then Exit(False);
        Offsets[PointIndex] := Nodes[NearestNode].P - Point;
      end;
      for PointIndex := FirstEditable to N - 1 - FirstEditable do
      begin
        Change := PointF(0, 0);
        for Offset := -2 to 2 do
        begin
          Neighbour := EnsureRange(PointIndex + Offset, 0, N - 1);
          Blend := 3 - Abs(Offset);
          Change.X := Change.X + Offsets[Neighbour].X * Blend / 9;
          Change.Y := Change.Y + Offsets[Neighbour].Y * Blend / 9;
        end;
        Targets[I][PointIndex] := PointF(Targets[I][PointIndex].X + Change.X * 0.85,
          Targets[I][PointIndex].Y + Change.Y * 0.85);
      end;
    end;
    Result := True;
  end;
begin
  Result:=False; Original:=Copy(Targets);
  for I:=0 to High(Targets) do
  begin
    Targets[I]:=Copy(Original[I]); N:=Length(Targets[I]); if N<2 then Exit;
    OldLength:=PathLength(Original[I]); SetLength(Offsets,N);
    if not EndpointsFirst and not PullToCenterline then Exit;
    Closed:=Distance(Original[I][0],Original[I][N-1])<3;
    for EndIndex:=0 to 1 do
    begin
      J:=0; if EndIndex=1 then J:=N-1; P:=Original[I][J];
      if EndIndex=0 then Direction:=PointF(Original[I][1].X-P.X,Original[I][1].Y-P.Y)
      else Direction:=PointF(P.X-Original[I][N-2].X,P.Y-Original[I][N-2].Y);
      Len:=Max(0.001,Hypot(Direction.X,Direction.Y)); Direction.X:=Direction.X/Len; Direction.Y:=Direction.Y/Len;
      Connected:=False;
      for K:=0 to High(Original) do if K<>I then
        for V:=0 to High(Original[K]) do if Distance(P,Original[K][V])<=2.5 then begin Connected:=True; Break end;
      Best:=1E30; BestNode:=-1;
      if not Closed then for K:=0 to High(Nodes) do
      begin
        if (Nodes[K].Count<>1) and not (Connected and (Nodes[K].Count>=3)) then Continue;
        D:=Squared(P,Nodes[K].P); if D>576 then Continue;
        Cosine:=-1;
        for V:=0 to Nodes[K].Count-1 do
        begin
          Anchor:=Nodes[Nodes[K].Neighbours[V]].P;
          Vector:=PointF(Anchor.X-Nodes[K].P.X,Anchor.Y-Nodes[K].P.Y);
          if EndIndex=1 then begin Vector.X:=-Vector.X; Vector.Y:=-Vector.Y end;
          Len:=Max(0.001,Hypot(Vector.X,Vector.Y)); Cosine:=Max(Cosine,(Vector.X*Direction.X+Vector.Y*Direction.Y)/Len);
        end;
        Score:=D+64*Sqr(1-Cosine);
        if Score<Best then begin Best:=Score; BestNode:=K end;
      end;
      if BestNode<0 then
      begin
        Best:=1E30;
        for K:=0 to High(Nodes) do
        begin D:=Squared(Targets[I][J],Nodes[K].P); if D<Best then begin Best:=D; BestNode:=K end end;
      end;
      if BestNode<0 then Exit;
      Delta:=PointF(Nodes[BestNode].P.X-Targets[I][J].X,Nodes[BestNode].P.Y-Targets[I][J].Y);
      for K:=0 to N-1 do
      begin
        F:=K/(N-1); if EndIndex=0 then F:=1-F;
        if EndpointsFirst then Weight:=F else Weight:=F*F*F;
        Targets[I][K]:=PointF(Targets[I][K].X+Delta.X*Weight,Targets[I][K].Y+Delta.Y*Weight);
      end;
    end;
    // 先に端点を合わせると、交差に差しかかる前の区間が別の画へ引かれにくい。
    if EndpointsFirst and not PullToCenterline then Exit;
    for J:=0 to N-1 do if Distance(Targets[I][J],Original[I][J])>24 then Exit;
    Len:=PathLength(Targets[I]); if (Len<OldLength*0.6) or (Len>OldLength*1.6) then Exit;
  end;
  Result:=True;
end;

// 近い軌道を逆向きにたどる折り返しを、字形の行き止まりに対応させる。
// Guideは呼出側所有の案内線。探索用にだけ変形し、出力経路には使わない。
procedure MoveGuideAnchor(var Guide: TPoints; const Anchor: TFoldAnchor; const P: TPointF);
var I, HalfWindow: Integer; Offset: TPointF; Weight: Double;
begin
  Offset:=P-Guide[Anchor.Stage];
  HalfWindow:=Min(8,Min(Anchor.Stage,High(Guide)-Anchor.Stage));
  for I:=Anchor.Stage-HalfWindow+1 to Anchor.Stage+HalfWindow-1 do
  begin
    Weight:=1-Abs(I-Anchor.Stage)/HalfWindow;
    Guide[I]:=Guide[I]+PointF(Offset.X*Weight,Offset.Y*Weight);
  end;
end;

function AnchorFold(const Nodes: TNodes; var Guide: TPoints; out Anchor: TFoldAnchor;
  FirstStage: Integer = 0; LastStage: Integer = MaxInt): Boolean;
const
  LookAround = 3;
  SnapRadius = 18.0;
var
  I: Integer;
  A, B, Turn: TPointF;
  Cosine, Best, Dist: Double;
begin
  Anchor.Stage := -1;
  Anchor.Node := -1;
  Best := -0.85;
  for I := Max(LookAround, FirstStage) to Min(High(Guide) - LookAround, LastStage) do
  begin
    A := Guide[I] - Guide[I - LookAround];
    B := Guide[I + LookAround] - Guide[I];
    if Distance(Guide[I - LookAround], Guide[I + LookAround]) > 5 then Continue;
    Cosine := (A.X * B.X + A.Y * B.Y) / Max(0.001, Hypot(A.X, A.Y) * Hypot(B.X, B.Y));
    if Cosine < Best then
    begin
      Anchor.Stage := I;
      Best := Cosine;
    end;
  end;
  if Anchor.Stage < 0 then Exit(False);

  Turn := Guide[Anchor.Stage];
  Best := SnapRadius;
  for I := 0 to High(Nodes) do
    if Nodes[I].Count = 1 then
    begin
      Dist := Distance(Nodes[I].P, Turn);
      if Dist < Best then
      begin
        Best := Dist;
        Anchor.Node := I;
      end;
    end;
  if Anchor.Node < 0 then Exit(False);

  MoveGuideAnchor(Guide,Anchor,Nodes[Anchor.Node].P);
  Result := True;
end;

function AnchorValley(const Nodes: TNodes; var Guide: TPoints; FirstStage, LastStage: Integer;
  out Anchor: TFoldAnchor): Boolean;
var I: Integer; Turn, P: TPointF; Score, Best: Double;
begin
  Anchor.Stage:=FirstStage;
  for I:=FirstStage+1 to LastStage do
    if Guide[I].Y>Guide[Anchor.Stage].Y then Anchor.Stage:=I;
  Turn:=Guide[Anchor.Stage]; Best:=1E30; Anchor.Node:=-1;
  for I:=0 to High(Nodes) do
  begin
    P:=Nodes[I].P;
    if (Abs(P.X-Turn.X)>9) or (Abs(P.Y-Turn.Y)>18) then Continue;
    Score:=Sqr(P.X-Turn.X)*0.18-P.Y;
    if Score<Best then begin Best:=Score; Anchor.Node:=I end;
  end;
  Result:=Anchor.Node>=0;
  if Result then MoveGuideAnchor(Guide,Anchor,Nodes[Anchor.Node].P);
end;

function CountRetracedEdges(const Path: TPoints; const FoldPoint: TPointF; out Travel: Double): Integer;
var Turn: Integer;
begin
  Result := 0;
  Travel := 0;
  Turn := 0;
  while (Turn < High(Path)) and (Distance(Path[Turn], FoldPoint) > 0.001) do Inc(Turn);
  while (Result < Min(Turn, High(Path) - Turn)) and
    (Distance(Path[Turn - Result - 1], Path[Turn + Result + 1]) < 0.001) do
  begin
    Travel := Travel + Distance(Path[Turn + Result], Path[Turn + Result + 1]);
    Inc(Result);
  end;
end;

// 離散Frechet型の積グラフ探索。状態は(参照上の進行位置,実フォント中心線の節点)。
// 紙面上の位置誤差・移動方向・進行距離を評価し、交差でも参照の曲がり方を追う。
function TraceReference(const Nodes: TNodes; const Target: TPoints; out Path: TPoints;
  out PathStages: TArray<Integer>; TrackStages: Boolean; const Fold, EarlierFold: TFoldAnchor;
  ExactEnd: Boolean): Boolean;
var Costs: TArray<Double>; Previous,Heap,Positions: TArray<Integer>; Reverse: TList<Integer>;
  NV,NS,HeapCount,I,J,State,Stage,V,Next,Last,EndState,At,Parent,Child,Temp: Integer;
  Leash,MinStart,MinEnd,EndSlack,D,Step,Cost,DX,DY,VX,VY,Len,Dir: Double;
  function Squared(const A,B: TPointF): Double; inline;
  begin Result:=Sqr(A.X-B.X)+Sqr(A.Y-B.Y) end;
  procedure Offer(ID,FromID: Integer; Value: Double);
  var P,Q,T: Integer;
  begin
    if Value>=Costs[ID] then Exit;
    Costs[ID]:=Value; Previous[ID]:=FromID; P:=Positions[ID];
    if P<0 then begin P:=HeapCount; Inc(HeapCount); Heap[P]:=ID; Positions[ID]:=P end;
    while P>0 do
    begin
      Q:=(P-1) div 2; if Costs[Heap[Q]]<=Value then Break;
      T:=Heap[Q]; Heap[Q]:=ID; Heap[P]:=T; Positions[T]:=P; Positions[ID]:=Q; P:=Q;
    end;
  end;
begin
  Result:=False; Path:=nil; PathStages:=nil; NV:=Length(Nodes); NS:=NV*Length(Target);
  if (NV=0) or (NS=0) or (NS>524288) then Exit;
  Leash:=12; SetLength(Costs,NS); SetLength(Previous,NS); SetLength(Heap,NS); SetLength(Positions,NS);
  for I:=0 to NS-1 do begin Costs[I]:=1E30; Previous[I]:=-1; Positions[I]:=-1 end;
  MinStart:=1E30; MinEnd:=1E30; HeapCount:=0; Last:=High(Target); EndState:=-1;
  for I:=0 to NV-1 do
  begin MinStart:=Min(MinStart,Squared(Nodes[I].P,Target[0])); MinEnd:=Min(MinEnd,Squared(Nodes[I].P,Target[Last])) end;
  if (MinStart>64) or (MinEnd>64) then Exit;
  if ExactEnd then EndSlack:=0 else EndSlack:=2.25;
  for I:=0 to NV-1 do
  begin D:=Squared(Nodes[I].P,Target[0]); if D<=MinStart+2.25 then Offer(I,-1,D*2) end;
  while HeapCount>0 do
  begin
    State:=Heap[0]; Dec(HeapCount); Positions[State]:=-2;
    if HeapCount>0 then
    begin
      Heap[0]:=Heap[HeapCount]; Positions[Heap[0]]:=0; At:=0;
      while At*2+1<HeapCount do
      begin
        Child:=At*2+1;
        if (Child+1<HeapCount) and (Costs[Heap[Child+1]]<Costs[Heap[Child]]) then Inc(Child);
        if Costs[Heap[At]]<=Costs[Heap[Child]] then Break;
        Temp:=Heap[At]; Heap[At]:=Heap[Child]; Heap[Child]:=Temp;
        Positions[Heap[At]]:=At; Positions[Heap[Child]]:=Child; At:=Child;
      end;
    end;
    Stage:=State div NV; V:=State mod NV;
    if (Stage=Last) and (Squared(Nodes[V].P,Target[Last])<=MinEnd+EndSlack) then begin EndState:=State; Break end;
    if (Stage<Last) and ((Stage+1<>Fold.Stage) or (V=Fold.Node)) and
      ((Stage+1<>EarlierFold.Stage) or (V=EarlierFold.Node)) then
    begin
      Next:=State+NV; D:=Squared(Nodes[V].P,Target[Stage+1]);
      if (D<=Sqr(Leash)) and (Positions[Next]<>-2) then
      begin Step:=Distance(Target[Stage],Target[Stage+1]); Offer(Next,State,Costs[State]+Step*(0.35+D/16)) end;
    end;
    DX:=Target[Min(Last,Stage+1)].X-Target[Max(0,Stage-1)].X;
    DY:=Target[Min(Last,Stage+1)].Y-Target[Max(0,Stage-1)].Y; Len:=Hypot(DX,DY);
    for J:=0 to Nodes[V].Count-1 do
    begin
      I:=Nodes[V].Neighbours[J]; Next:=Stage*NV+I; D:=Squared(Nodes[I].P,Target[Stage]);
      if (D>Sqr(Leash)) or (Positions[Next]=-2) then Continue;
      VX:=Nodes[I].P.X-Nodes[V].P.X; VY:=Nodes[I].P.Y-Nodes[V].P.Y; Step:=Hypot(VX,VY); Dir:=0;
      if Len>0.001 then Dir:=1-(DX*VX+DY*VY)/(Len*Step);
      Cost:=Costs[State]+Step*(0.35+D/16+Dir*1.5); Offer(Next,State,Cost);
    end;
  end;
  if EndState<0 then Exit;
  Reverse:=TList<Integer>.Create;
  try
    State:=EndState; Parent:=-1;
    while State>=0 do
    begin V:=State mod NV; if V<>Parent then Reverse.Add(State); Parent:=V; State:=Previous[State] end;
    if Reverse.Count=1 then Reverse.Add(Reverse[0]);
    SetLength(Path,Reverse.Count);
    if TrackStages then SetLength(PathStages,Reverse.Count);
    for I:=0 to Reverse.Count-1 do
    begin
      State:=Reverse[Reverse.Count-1-I];
      Path[I]:=Nodes[State mod NV].P;
      if TrackStages then PathStages[I]:=State div NV;
    end;
  finally Reverse.Free end;
  D:=PathLength(Path); Step:=PathLength(Target);
  Result:=(D>=Max(0,Step*0.4-2)) and (D<=Step*1.8+3);
end;

function OrderedError(const Targets: TPaths; const Strokes: TArray<TStroke>): Double;
var I,J,N: Integer; A,B: TPoints;
begin
  N:=Min(Length(Targets),Length(Strokes)); Result:=Abs(Length(Targets)-Length(Strokes))*20;
  if N=0 then Exit(1000);
  for I:=0 to N-1 do
  begin
    A:=Samples(Targets[I],32); B:=Samples(Strokes[I].Points,32);
    if Length(B)<>32 then Exit(1000);
    for J:=0 to 31 do Result:=Result+Distance(A[J],B[J])/(N*32);
  end;
end;

// セリフの張り出しを外接矩形と同一視せず、中心線への距離で位置と縦横比を登録する。
// 移動・拡縮は探索の手掛かりにだけ適用し、出力は常に元のフォント節点から選ぶ。
procedure AlignTargets(Glyph: TWritingGlyph; const Nodes: TNodes; var Targets: TPaths);
var Field: TArray<Double>; W,H,I,J,X,Y,K,Stage,Pass,Axis,Sign: Integer;
  Params,Trial: array[0..3] of Double; CX,CY,Step,Delta,Best,Score,Initial: Double;
  function Cost(const V: array of Double): Double;
  var A,B,N,IX,IY: Integer; P: TPointF; PX,PY,D: Double;
  begin
    Result:=0; N:=0;
    for A:=0 to High(Targets) do for B:=0 to High(Targets[A]) do
    begin
      P:=Targets[A][B]; PX:=(P.X-CX)*V[2]+CX+V[0]; PY:=(P.Y-CY)*V[3]+CY+V[1];
      IX:=EnsureRange(Round(PX),0,W-1); IY:=EnsureRange(Round(PY),0,H-1);
      D:=Field[IY*W+IX]+Abs(PX-IX)+Abs(PY-IY); Result:=Result+Sqr(Min(10,D)); Inc(N);
    end;
    Result:=Result/Max(1,N);
  end;
begin
  W:=Glyph.Width; H:=Glyph.Height; SetLength(Field,W*H);
  for I:=0 to High(Field) do Field[I]:=1000;
  for I:=0 to High(Nodes) do Field[Round(Nodes[I].P.Y)*W+Round(Nodes[I].P.X)]:=0;
  for Y:=0 to H-1 do for X:=0 to W-1 do
  begin
    K:=Y*W+X;
    if X>0 then Field[K]:=Min(Field[K],Field[K-1]+1);
    if Y>0 then
    begin
      Field[K]:=Min(Field[K],Field[K-W]+1);
      if X>0 then Field[K]:=Min(Field[K],Field[K-W-1]+Sqrt(2));
      if X<W-1 then Field[K]:=Min(Field[K],Field[K-W+1]+Sqrt(2));
    end;
  end;
  for Y:=H-1 downto 0 do for X:=W-1 downto 0 do
  begin
    K:=Y*W+X;
    if X<W-1 then Field[K]:=Min(Field[K],Field[K+1]+1);
    if Y<H-1 then
    begin
      Field[K]:=Min(Field[K],Field[K+W]+1);
      if X>0 then Field[K]:=Min(Field[K],Field[K+W-1]+Sqrt(2));
      if X<W-1 then Field[K]:=Min(Field[K],Field[K+W+1]+Sqrt(2));
    end;
  end;
  CX:=(W-1)/2; CY:=(H-1)/2; Params[0]:=0; Params[1]:=0; Params[2]:=1; Params[3]:=1;
  Best:=Cost(Params); Initial:=Best;
  for Stage:=0 to 2 do
  begin
    Step:=4/(1 shl Stage);
    for Pass:=0 to 7 do
    begin
      Score:=Best;
      for Axis:=0 to 3 do for Sign:=-1 to 1 do if Sign<>0 then
      begin
        Trial:=Params; Delta:=Step; if Axis>=2 then Delta:=Step/100;
        Trial[Axis]:=Trial[Axis]+Sign*Delta;
        if (Abs(Trial[0])>10) or (Abs(Trial[1])>10) or (Trial[2]<0.8) or (Trial[2]>1.2) or (Trial[3]<0.8) or (Trial[3]>1.2) then Continue;
        Delta:=Cost(Trial); if Delta+0.0001<Best then begin Params:=Trial; Best:=Delta end;
      end;
      if Best>=Score-0.0001 then Break;
    end;
  end;
  if Best>=Initial-0.05 then Exit;
  for I:=0 to High(Targets) do for J:=0 to High(Targets[I]) do
    Targets[I][J]:=PointF((Targets[I][J].X-CX)*Params[2]+CX+Params[0],(Targets[I][J].Y-CY)*Params[3]+CY+Params[1]);
end;

function ReconstructReference(Glyph: TWritingGlyph; const Strokes: TReferenceVariant;
  out Info: TReferenceFitInfo; out Targets: TPaths; Strategy: TFitStrategy;
  FoldStroke: Integer = -1; TwoFolds: Boolean = False): Boolean;
const NoFold: TFoldAnchor = (Stage: -1; Node: -1);
var Nodes: TNodes; Paths: TArray<TStroke>;
  I,J,K,Hit,Missed,Total,Repeated,Head,Tail,Retraced,EarlierRetraced,LoopRepeats: Integer;
  Fold, EarlierFold: TFoldAnchor;
  RLo,RHi,GLo,GHi,P: TPointF;
  Covered,Visited: TArray<Boolean>; Queue,PathStages,SerifVisited: TArray<Integer>;
  AnyCovered,TrackLoop,MeasureOverlap,ExactEnd,AllowSerifs,TraceValleys: Boolean;
  Candidate: TPoints; Best,Average,Worst: Double; Edges: TDictionary<Int64,Integer>; Key: Int64;
  EdgeLength, TotalLength, RepeatedLength, RetracedLength, EarlierLength: Double;
  function NodeNumber(const Q: TPointF): Integer;
  begin Result:=Round(Q.Y)*Glyph.Width+Round(Q.X) end;
  function ConnectedSerif(Index: Integer): Boolean;
  var Origin, Q: TPointF; Head, Tail, V, Next, N, Visit: Integer; MaxRise: Double;
  begin
    // 短い横向きの飾りは、同じ中心線をたどって筆記経路へ届く場合だけ許容する。
    Origin:=Nodes[Index].P; Visit:=Index+1; MaxRise:=5;
    // w の中央上端にあるセリフは、二つの斜線より上に突き出すことがある。
    if (Pos(Glyph.Character,'wW')>0) and (Origin.Y<GLo.Y+(GHi.Y-GLo.Y)*0.25) then MaxRise:=16;
    Head:=0; Tail:=1; Queue[0]:=Index; SerifVisited[Index]:=Visit;
    while Head<Tail do
    begin
      V:=Queue[Head]; Inc(Head);
      if Covered[V] then Exit(True);
      for N:=0 to Nodes[V].Count-1 do
      begin
        Next:=Nodes[V].Neighbours[N]; Q:=Nodes[Next].P;
        if (SerifVisited[Next]=Visit) or (Abs(Q.X-Origin.X)>16) or (Abs(Q.Y-Origin.Y)>MaxRise) then Continue;
        SerifVisited[Next]:=Visit; Queue[Tail]:=Next; Inc(Tail);
      end;
    end;
    Result:=False;
  end;
  function CountLoopRepeats(const Path, Guide: TPoints): Integer;
  var
    FirstVisit: TDictionary<Int64,Integer>;
    Edge: Int64;
    PointIndex, PreviousStage, Stage: Integer;
    Step, FirstDirection, Direction: TPointF;
  begin
    Result := 0;
    FirstVisit := TDictionary<Int64,Integer>.Create;
    try
      for PointIndex := 1 to High(Path) do
      begin
        Edge := Int64(NodeNumber(Path[PointIndex - 1])) * Length(Glyph.Mask) + NodeNumber(Path[PointIndex]);
        Stage := PathStages[PointIndex];
        if not FirstVisit.TryGetValue(Edge, PreviousStage) then
        begin
          FirstVisit.Add(Edge, Stage);
          Continue;
        end;
        if (Stage - PreviousStage < 5) or (Distance(Guide[PreviousStage], Guide[Stage]) > 10) then Continue;
        Step := Path[PointIndex] - Path[PointIndex - 1];
        FirstDirection := Guide[Min(High(Guide), PreviousStage + 1)] - Guide[Max(0, PreviousStage - 1)];
        Direction := Guide[Min(High(Guide), Stage + 1)] - Guide[Max(0, Stage - 1)];
        if (FirstDirection.X * Step.X + FirstDirection.Y * Step.Y > 0) and
          (Direction.X * Step.X + Direction.Y * Step.Y > 0) then Inc(Result);
      end;
    finally
      FirstVisit.Free;
    end;
  end;
begin
  Result:=False; Targets:=nil; Info:=Default(TReferenceFitInfo);
  Info.Available:=True; Info.Reason:='shape-mismatch';
  if (Glyph.Width<2) or (Glyph.Height<2) or (Length(Glyph.Mask)<>Glyph.Width*Glyph.Height) then Exit;
  Nodes:=BuildGraph(Glyph,Info.RecoveredComponents); if (Length(Nodes)<2) or (Length(Nodes)>4096) then Exit;
  if Strategy>=fsRepair then Info.RepairedEdges:=RepairGraphNeighbours(Glyph,Nodes);
  AllowSerifs:=Strategy in [fsSerifs,fsSerifComponents];
  TraceValleys:=AllowSerifs and (Pos(Glyph.Character,'vwVW')>0);
  RLo:=PointF(1E9,1E9); RHi:=PointF(-1E9,-1E9); GLo:=RLo; GHi:=RHi;
  for I:=0 to High(Strokes) do for P in Strokes[I].Points do
  begin RLo.X:=Min(RLo.X,P.X); RLo.Y:=Min(RLo.Y,P.Y); RHi.X:=Max(RHi.X,P.X); RHi.Y:=Max(RHi.Y,P.Y) end;
  for I:=0 to High(Nodes) do
  begin P:=Nodes[I].P; GLo.X:=Min(GLo.X,P.X); GLo.Y:=Min(GLo.Y,P.Y); GHi.X:=Max(GHi.X,P.X); GHi.Y:=Max(GHi.Y,P.Y) end;
  SetLength(Targets,Length(Strokes)); SetLength(Paths,Length(Targets));
  for I:=0 to High(Targets) do
  begin
    Candidate:=Copy(Strokes[I].Points);
    for J:=0 to High(Candidate) do
      Candidate[J]:=PointF(GLo.X+(Candidate[J].X-RLo.X)*(GHi.X-GLo.X)/Max(0.001,RHi.X-RLo.X),
        GLo.Y+(Candidate[J].Y-RLo.Y)*(GHi.Y-GLo.Y)/Max(0.001,RHi.Y-RLo.Y));
    if AllowSerifs and (RHi.X-RLo.X<0.001) then
      for J:=0 to High(Candidate) do Candidate[J].X:=(GLo.X+GHi.X)*0.5;
    Targets[I]:=Samples(Candidate,EnsureRange(Ceil(PathLength(Candidate)/2.5)+1,12,100));
  end;
  if Strategy in [fsComponents, fsCompactComponents, fsSerifComponents] then
  begin
    if not AlignReferenceComponents(Nodes,Targets,Strategy<>fsComponents,Strategy=fsSerifComponents) then
      begin Info.Reason:='component-mismatch'; Exit end;
    Info.AdaptedGuide:=True;
    if Strategy=fsCompactComponents then AlignTargets(Glyph,Nodes,Targets);
  end
  else if Strategy<>fsBounds then AlignTargets(Glyph,Nodes,Targets);
  if (Strategy in [fsAdapt, fsCompactComponents, fsFold, fsEndpoints]) or
    ((Strategy=fsSerifs) and (Glyph.Character<>'l')) then
  begin
    if not AdaptGuides(Nodes,Targets,Strategy in [fsEndpoints,fsSerifs]) then
      begin Info.Reason:='guide-mismatch'; Exit end;
    Info.AdaptedGuide:=True;
  end;
  Retraced:=0; LoopRepeats:=0; RetracedLength:=0;
  for I:=0 to High(Targets) do
  begin
    Fold:=NoFold; EarlierFold:=NoFold;
    if I=FoldStroke then
    begin
      if not AnchorFold(Nodes,Targets[I],Fold) then
        begin Info.Reason:='fold-mismatch'; Exit end;
      // 「ゑ」の印刷体候補では、前半の左の折り返しも実字形の端へ合わせる。
      if TwoFolds and
        (not AnchorFold(Nodes,Targets[I],EarlierFold,Length(Targets[I]) div 6,Length(Targets[I]) div 2) or
         (EarlierFold.Stage>=Fold.Stage) or (EarlierFold.Node=Fold.Node)) then
        begin Info.Reason:='fold-mismatch'; Exit end;
    end;
    if TraceValleys then
    begin
      J:=High(Targets[I]);
      if Pos(Glyph.Character,'wW')>0 then
      begin
        if not AnchorValley(Nodes,Targets[I],J div 6,J div 2,EarlierFold) or
          not AnchorValley(Nodes,Targets[I],J div 2+1,J*5 div 6,Fold) then
          begin Info.Reason:='valley-mismatch'; Exit end;
      end
      else if not AnchorValley(Nodes,Targets[I],J div 4,J*3 div 4,Fold) then
        begin Info.Reason:='valley-mismatch'; Exit end;
    end;
    TrackLoop := (Glyph.Character = 'む') and (I = 1);
    // 「わ」の左の縦画は、合わせた終点の直前で止めずに先端まで書く。
    ExactEnd := (Glyph.Character = 'わ') and (I = 0) and (FoldStroke >= 0);
    if not TraceReference(Nodes,Targets[I],Candidate,PathStages,TrackLoop,Fold,EarlierFold,ExactEnd) then
      begin Info.Reason:='trace-mismatch-'+IntToStr(I+1); Exit end;
    if TrackLoop then LoopRepeats := CountLoopRepeats(Candidate, Targets[I]);
    if Fold.Node>=0 then
    begin
      // 予定の折り返しの両側で同じ辺を逆に通る区間だけ、重複の許容分にする。
      Retraced:=CountRetracedEdges(Candidate,Nodes[Fold.Node].P,RetracedLength);
      if (Retraced=0) and not TraceValleys then begin Info.Reason:='fold-mismatch'; Exit end;
      if EarlierFold.Node>=0 then
      begin
        EarlierRetraced:=CountRetracedEdges(Candidate,Nodes[EarlierFold.Node].P,EarlierLength);
        if (EarlierRetraced=0) and not TraceValleys then begin Info.Reason:='fold-mismatch'; Exit end;
        Inc(Retraced,EarlierRetraced);
        RetracedLength:=RetracedLength+EarlierLength;
      end;
    end;
    Paths[I]:=Default(TStroke); Paths[I].ID:=I; Paths[I].Points:=Candidate;
    Average:=0; Worst:=0;
    for P in Targets[I] do
    begin
      Best:=1E30; for J:=0 to High(Candidate) do Best:=Min(Best,Distance(P,Candidate[J]));
      Average:=Average+Best/Length(Targets[I]); Worst:=Max(Worst,Best);
    end;
    if (Average>4.5) or (Worst>10) then begin Info.Reason:='distance-mismatch-'+IntToStr(I+1); Exit end;
  end;
  // 未対応の枝・接続が多いフォントは無理に画数を合わせない。マスクの変更も行わない。
  Missed:=0; SetLength(Covered,Length(Nodes));
  for K:=0 to High(Nodes) do
  begin
    Best:=1E30;
    for I:=0 to High(Paths) do for P in Paths[I].Points do Best:=Min(Best,Distance(Nodes[K].P,P));
    Covered[K]:=Best<=3.5;
  end;
  SetLength(Queue,Length(Nodes));
  if AllowSerifs then SetLength(SerifVisited,Length(Nodes));
  for K:=0 to High(Nodes) do
    if not Covered[K] and (not AllowSerifs or not ConnectedSerif(K)) then Inc(Missed);
  Info.Coverage:=1-Missed/Length(Nodes);
  if Info.Coverage<0.92 then begin Info.Reason:='uncovered-shape'; Exit end;
  SetLength(Visited,Length(Nodes));
  for I:=0 to High(Nodes) do if not Visited[I] then
  begin
    Head:=0; Tail:=1; Queue[0]:=I; Visited[I]:=True; AnyCovered:=False;
    while Head<Tail do
    begin
      K:=Queue[Head]; Inc(Head); AnyCovered:=AnyCovered or Covered[K];
      for J:=0 to Nodes[K].Count-1 do
      begin Hit:=Nodes[K].Neighbours[J]; if not Visited[Hit] then begin Visited[Hit]:=True; Queue[Tail]:=Hit; Inc(Tail) end end;
    end;
    if not AnyCovered then begin Info.Reason:='missing-component'; Exit end;
  end;
  // 「れ」「わ」の折り返しでは、斜め移動も実際の距離で数えて重複の割合を確認する。
  MeasureOverlap:=(Pos(Glyph.Character,'れわ')>0) and (FoldStroke>=0);
  Total:=0; Repeated:=0; TotalLength:=0; RepeatedLength:=0;
  Edges:=TDictionary<Int64,Integer>.Create;
  try
    for I:=0 to High(Paths) do for J:=1 to High(Paths[I].Points) do
    begin
      K:=NodeNumber(Paths[I].Points[J-1]); Hit:=NodeNumber(Paths[I].Points[J]); if K=Hit then Continue;
      Key:=Int64(Min(K,Hit))*Int64(Glyph.Width*Glyph.Height)+Max(K,Hit); Inc(Total);
      if MeasureOverlap then
      begin
        EdgeLength:=Distance(Paths[I].Points[J-1],Paths[I].Points[J]);
        TotalLength:=TotalLength+EdgeLength;
      end;
      if Edges.ContainsKey(Key) then
      begin
        Inc(Repeated);
        if MeasureOverlap then RepeatedLength:=RepeatedLength+EdgeLength;
      end
      else Edges.Add(Key,1);
    end;
  finally Edges.Free end;
  // 折り返しと、参照でも同じ方向に通る輪の重なりを除いて重複を評価する。
  if (Repeated-Retraced-LoopRepeats>Max(6,Total*0.08)) and
    (not MeasureOverlap or (RepeatedLength-RetracedLength>Max(6.0,TotalLength*0.08))) then
    begin Info.Reason:='ambiguous-overlap'; Exit end;
  Info.BeforeError:=OrderedError(Targets,Glyph.Strokes); Info.AfterError:=OrderedError(Targets,Paths);
  if (Info.AfterError>8) or (Info.AfterError+0.75>=Info.BeforeError) then begin Info.Reason:='no-clear-improvement'; Exit end;
  if AllowSerifs then
    case Glyph.Character[1] of
      'b', 'p', 'M', 'P', 'R': Paths[0].Points:=TrimTerminalSerifs(Paths[0].Points,True,True);
      'E', 'F':
        begin
          Paths[0].Points:=TrimTerminalSerifs(Paths[0].Points,True,True);
          for I:=1 to High(Paths) do Paths[I].Points:=TrimTerminalSerifs(Paths[I].Points,False,False);
        end;
      'L': Paths[0].Points:=TrimTerminalSerifs(Paths[0].Points,True,False);
      'N':
        begin
          Paths[0].Points:=TrimTerminalSerifs(Paths[0].Points,True,True);
          Paths[2].Points:=TrimTerminalSerifs(Paths[2].Points,True,True);
        end;
      'T': Paths[1].Points:=TrimTerminalSerifs(Paths[1].Points,True,True);
    end;
  Glyph.Strokes:=Paths; Glyph.ReferenceOrderOnly:=False;
  Info.Accepted:=True; Info.Mode:='paths'; Info.Reason:='accepted'; Result:=True;
end;

function TryCanonicalReference(Glyph: TWritingGlyph; const Strokes: TReferenceVariant;
  out Info: TReferenceFitInfo): Boolean;
var Targets,AlignedTargets: TPaths; Improvement: Double; AlignedInfo: TReferenceFitInfo;
begin
  Result:=ReconstructReference(Glyph,Strokes,Info,Targets,fsBounds); if Result then Exit;
  Result:=ReconstructReference(Glyph,Strokes,AlignedInfo,AlignedTargets,fsAlign);
  if Result then begin Info:=AlignedInfo; Exit end;
  if ((Length(Targets)>0) and ApplyReferenceOrder(Glyph,Targets,Improvement,Info.OrderReason)) or
     ((Length(AlignedTargets)>0) and ApplyReferenceOrder(Glyph,AlignedTargets,Improvement,Info.OrderReason)) then
  begin
    Info.Accepted:=True; Info.Mode:='order'; Info.Reason:='reference-order'; Info.Coverage:=1;
    Info.OrderImprovement:=Improvement; Glyph.ReferenceOrderOnly:=True; Result:=True;
    Exit;
  end;
  // 従来の採用結果を維持し、それでも不採用の字だけ接続復元と局所対応を試す。
  Result:=ReconstructReference(Glyph,Strokes,AlignedInfo,AlignedTargets,fsRepair);
  if not Result then Result:=ReconstructReference(Glyph,Strokes,AlignedInfo,AlignedTargets,fsComponents);
  if not Result then Result:=ReconstructReference(Glyph,Strokes,AlignedInfo,AlignedTargets,fsAdapt);
  if Result then Info:=AlignedInfo;
end;

function SuppressTrailingBranch(Glyph: TWritingGlyph; ExpectedCount: Integer): Boolean;
const
  MaxBranchLength = 6.0; // 128 em
  MaxRelativeLength = 0.12;
var
  Branch, Main: TPoints;
  I, J, K, Owner: Integer;
  BranchLength: Double;
begin
  Result := False;
  if Length(Glyph.Strokes) <> ExpectedCount + 1 then Exit;
  Branch := Glyph.Strokes[ExpectedCount].Points;
  BranchLength := PathLength(Branch);
  if (BranchLength <= 0) or (BranchLength > MaxBranchLength) then Exit;

  // 細線化の節点を一つだけ共有する突起を対象にする。離れた点、端点の続き、輪は別画のまま残す。
  Owner := -1;
  for I := 0 to ExpectedCount - 1 do
  begin
    Main := Glyph.Strokes[I].Points;
    for J := 0 to High(Main) do
      for K := 0 to High(Branch) do
        if (Main[J].X = Branch[K].X) and (Main[J].Y = Branch[K].Y) then
        begin
          if (Owner >= 0) or (J = 0) or (J = High(Main)) or
            ((K <> 0) and (K <> High(Branch))) then Exit;
          Owner := I;
        end;
  end;
  if (Owner < 0) or
    (BranchLength > PathLength(Glyph.Strokes[Owner].Points) * MaxRelativeLength) then Exit;

  // 字形マスクを残す。枝のインクは通常の露出計算で接続元の画とともに現れる。
  SetLength(Glyph.Strokes, ExpectedCount);
  Glyph.ReferenceOrderOnly := False;
  Result := True;
end;

function TryLatinPrintReference(Glyph: TWritingGlyph; const Reference: TStrokeReference;
  out Info: TReferenceFitInfo): Boolean;
var FirstVariant, I: Integer; Targets: TPaths;
begin
  if Glyph.Character='i' then
    Exit(ReconstructReference(Glyph,Reference.Variants[0],Info,Targets,fsSerifComponents));

  FirstVariant:=1;
  if Glyph.Character='g' then FirstVariant:=2; // 三画の既存候補はフォールバックへ残す。
  for I:=FirstVariant to High(Reference.Variants) do
    if ReconstructReference(Glyph,Reference.Variants[I],Info,Targets,fsSerifs) then
    begin
      Info.VariantIndex:=I;
      Exit(True);
    end;
  Result:=(Glyph.Character<>'g') and ReconstructReference(Glyph,Reference.Variants[0],Info,Targets,fsSerifs);
end;

function TryApplyStrokeReference(Glyph: TWritingGlyph; out Info: TReferenceFitInfo): Boolean;
var
  Reference: TStrokeReference;
  VariantInfo: TReferenceFitInfo;
  Targets: TPaths;
  VariantIndex, FoldStroke: Integer;
  PreferFullPaths, PreferFold: Boolean;
begin
  Result := False;
  Info := Default(TReferenceFitInfo);
  Info.Reason := 'no-reference';
  if (Length(Glyph.Character) <> 1) or Glyph.Missing or Glyph.Learned or
    not FindStrokeReference(Ord(Glyph.Character[1]), Reference) then Exit;

  // g の耳や b/p/N の端の飾りで余計な経路が生じる場合は、印刷体の候補を優先する。
  if ((Glyph.Character='g') or ((Pos(Glyph.Character,'bpN')>0) and
    (Length(Glyph.Strokes)>Length(Reference.Variants[0])))) and
    TryLatinPrintReference(Glyph,Reference,VariantInfo) then
  begin
    Info:=VariantInfo;
    Exit(True);
  end;

  // 「ヒ」は選択された右から左の書き方を優先する。
  if (Glyph.Character = 'ヒ') and (Length(Reference.Variants) > 1) and
    TryCanonicalReference(Glyph, Reference.Variants[1], Info) then
  begin
    Info.VariantIndex := 1;
    Exit(True);
  end;

  case Glyph.Character[1] of
    'て', 'で', 'ゑ', 'ん', 'ム': FoldStroke := 0;
    'え', 'ぇ', 'ね', 'れ', 'わ', 'を': FoldStroke := 1;
  else
    FoldStroke := -1;
  end;
  // 「わ」「を」「ん」「ム」は折り返しの先端を通る経路を先に探す。
  PreferFold := Pos(Glyph.Character, 'わをんム') > 0;
  if PreferFold then
    for VariantIndex := 0 to High(Reference.Variants) do
      if ReconstructReference(Glyph, Reference.Variants[VariantIndex], VariantInfo, Targets, fsFold, FoldStroke) then
      begin
        Info := VariantInfo;
        Info.VariantIndex := VariantIndex;
        Exit(True);
      end;

  Result := TryCanonicalReference(Glyph, Reference.Variants[0], Info);
  if (not Result or (Info.Mode='order')) and (Pos(Glyph.Character,'bdghiklmnpqruvwxAEFHKLMNPRTVWXY')>0) and
    TryLatinPrintReference(Glyph,Reference,VariantInfo) then
  begin
    Info:=VariantInfo;
    Exit(True);
  end;
  if not PreferFold and (FoldStroke >= 0) and (not Result or (Info.Mode = 'order')) and
    ReconstructReference(Glyph, Reference.Variants[0], VariantInfo, Targets, fsFold, FoldStroke) then
  begin
    Info := VariantInfo;
    Exit(True);
  end;
  // 接続や交差で分断された画は、順序補正を確定する前に全画の復元を試す。
  PreferFullPaths := Pos(Glyph.Character, 'かがゕけげゖふぶぷほぼぽむもゐゆゑりれゥネ') > 0;
  if (not Result or (Info.Mode = 'order')) and PreferFullPaths then
    if (Result and
        (ReconstructReference(Glyph, Reference.Variants[0], VariantInfo, Targets, fsRepair) or
         ReconstructReference(Glyph, Reference.Variants[0], VariantInfo, Targets, fsAdapt) or
         ReconstructReference(Glyph, Reference.Variants[0], VariantInfo, Targets, fsComponents))) or
       ReconstructReference(Glyph, Reference.Variants[0], VariantInfo, Targets, fsCompactComponents) or
       ReconstructReference(Glyph, Reference.Variants[0], VariantInfo, Targets, fsEndpoints) then
    begin
      Info := VariantInfo;
      Exit(True);
    end;
  if Result and ((Info.Mode <> 'order') or not PreferFullPaths) then Exit;

  // 字体違いは全画が照合できるときだけ採用する。正準の参照で採用済みの経路を優先する。
  for VariantIndex := 1 to High(Reference.Variants) do
    if ReconstructReference(Glyph, Reference.Variants[VariantIndex], VariantInfo, Targets, fsRepair) or
       ReconstructReference(Glyph, Reference.Variants[VariantIndex], VariantInfo, Targets, fsComponents) or
       ReconstructReference(Glyph, Reference.Variants[VariantIndex], VariantInfo, Targets, fsAdapt) or
       ReconstructReference(Glyph, Reference.Variants[VariantIndex], VariantInfo, Targets, fsCompactComponents) or
       (PreferFullPaths and ReconstructReference(Glyph, Reference.Variants[VariantIndex],
         VariantInfo, Targets, fsEndpoints)) or
       ((Glyph.Character = 'れ') and
        ReconstructReference(Glyph, Reference.Variants[VariantIndex], VariantInfo, Targets, fsFold, 1)) or
       ((Glyph.Character = 'ゑ') and
        (ReconstructReference(Glyph, Reference.Variants[VariantIndex], VariantInfo, Targets, fsFold, 0) or
         ReconstructReference(Glyph, Reference.Variants[VariantIndex], VariantInfo, Targets, fsFold, 0, True))) then
    begin
      Info := VariantInfo;
      Info.VariantIndex := VariantIndex;
      Exit(True);
    end;
  if Result then Exit;

  if SuppressTrailingBranch(Glyph, Length(Reference.Variants[0])) then
  begin
    Info := Default(TReferenceFitInfo);
    Info.Available := True;
    Info.Accepted := True;
    Info.Mode := 'trim';
    Info.Reason := 'trailing-branch';
    Result := True;
  end;
end;

end.
