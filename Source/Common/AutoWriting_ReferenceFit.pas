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

function PathLength(const A: TPoints): Double;
var I: Integer;
begin Result:=0; for I:=1 to High(A) do Result:=Result+Distance(A[I-1],A[I]) end;

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

function AlignReferenceComponents(const Nodes: TNodes; var Targets: TPaths): Boolean;
var Labels,Queue,Parents,Groups,RootGroups,Choices,Assigned: TArray<Integer>;
  RLo,RHi,NLo,NHi: TPoints; Costs: TArray<Double>; I,J,K,V,Head,Tail,NC,RC,A,B,Mask,Next,Stage: Integer;
  P,Q,RCenter,NCenter,Scale: TPointF; D,Best,DX,DY: Double;
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
    if (Scale.X<0.4) or (Scale.X>2.5) or (Scale.Y<0.4) or (Scale.Y>2.5) then Exit;
    RCenter:=PointF((RLo[A].X+RHi[A].X)/2,(RLo[A].Y+RHi[A].Y)/2);
    NCenter:=PointF((NLo[B].X+NHi[B].X)/2,(NLo[B].Y+NHi[B].Y)/2);
    for J:=0 to High(Targets[I]) do Targets[I][J]:=PointF((Targets[I][J].X-RCenter.X)*Scale.X+NCenter.X,(Targets[I][J].Y-RCenter.Y)*Scale.Y+NCenter.Y);
  end;
  Result:=True;
end;

// 字体差による局所的な位置ずれを滑らかに補正する。これは探索用の案内線のみ。
// 開いた画の始終点は、参照の接続関係と進行方向に合う実フォントの端点へ対応させる。
function AdaptGuides(const Nodes: TNodes; var Targets: TPaths): Boolean;
var Original: TPaths; Offsets: TPoints; I,J,K,Pass,T,EndIndex,N,BestNode,V: Integer;
  P,Delta,Direction,Vector,Anchor: TPointF; Best,D,Len,Cosine,Score,F,Weight,OldLength: Double;
  Connected,Closed: Boolean;
  function Squared(const A,B: TPointF): Double;
  begin Result:=Sqr(A.X-B.X)+Sqr(A.Y-B.Y) end;
begin
  Result:=False; Original:=Copy(Targets);
  for I:=0 to High(Targets) do
  begin
    Targets[I]:=Copy(Original[I]); N:=Length(Targets[I]); if N<2 then Exit;
    OldLength:=PathLength(Original[I]); SetLength(Offsets,N);
    for Pass:=0 to 1 do
    begin
      for J:=0 to N-1 do
      begin
        P:=Targets[I][J]; Best:=1E30; BestNode:=-1;
        for K:=0 to High(Nodes) do
        begin D:=Squared(P,Nodes[K].P); if D<Best then begin Best:=D; BestNode:=K end end;
        if (BestNode<0) or (Best>400) then Exit;
        Offsets[J]:=PointF(Nodes[BestNode].P.X-P.X,Nodes[BestNode].P.Y-P.Y);
      end;
      for J:=0 to N-1 do
      begin
        Delta:=PointF(0,0);
        for T:=-2 to 2 do
        begin K:=EnsureRange(J+T,0,N-1); Weight:=3-Abs(T); Delta.X:=Delta.X+Offsets[K].X*Weight/9; Delta.Y:=Delta.Y+Offsets[K].Y*Weight/9 end;
        Targets[I][J]:=PointF(Targets[I][J].X+Delta.X*0.85,Targets[I][J].Y+Delta.Y*0.85);
      end;
    end;
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
        F:=K/(N-1); if EndIndex=0 then F:=1-F; Weight:=F*F*F;
        Targets[I][K]:=PointF(Targets[I][K].X+Delta.X*Weight,Targets[I][K].Y+Delta.Y*Weight);
      end;
    end;
    for J:=0 to N-1 do if Distance(Targets[I][J],Original[I][J])>24 then Exit;
    Len:=PathLength(Targets[I]); if (Len<OldLength*0.6) or (Len>OldLength*1.6) then Exit;
  end;
  Result:=True;
end;

// 離散Frechet型の積グラフ探索。状態は(参照上の進行位置,実フォント中心線の節点)。
// 紙面上の位置誤差・移動方向・進行距離を評価し、交差でも参照の曲がり方を追う。
function TraceReference(const Nodes: TNodes; const Target: TPoints; out Path: TPoints): Boolean;
var Costs: TArray<Double>; Previous,Heap,Positions: TArray<Integer>; Reverse: TList<Integer>;
  NV,NS,HeapCount,I,J,State,Stage,V,Next,Last,EndState,At,Parent,Child,Temp: Integer;
  Leash,MinStart,MinEnd,D,Step,Cost,DX,DY,VX,VY,Len,Dir: Double;
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
  Result:=False; Path:=nil; NV:=Length(Nodes); NS:=NV*Length(Target);
  if (NV=0) or (NS=0) or (NS>524288) then Exit;
  Leash:=12; SetLength(Costs,NS); SetLength(Previous,NS); SetLength(Heap,NS); SetLength(Positions,NS);
  for I:=0 to NS-1 do begin Costs[I]:=1E30; Previous[I]:=-1; Positions[I]:=-1 end;
  MinStart:=1E30; MinEnd:=1E30; HeapCount:=0; Last:=High(Target); EndState:=-1;
  for I:=0 to NV-1 do
  begin MinStart:=Min(MinStart,Squared(Nodes[I].P,Target[0])); MinEnd:=Min(MinEnd,Squared(Nodes[I].P,Target[Last])) end;
  if (MinStart>64) or (MinEnd>64) then Exit;
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
    if (Stage=Last) and (Squared(Nodes[V].P,Target[Last])<=MinEnd+2.25) then begin EndState:=State; Break end;
    if Stage<Last then
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
    begin V:=State mod NV; if V<>Parent then Reverse.Add(V); Parent:=V; State:=Previous[State] end;
    if Reverse.Count=1 then Reverse.Add(Reverse[0]);
    SetLength(Path,Reverse.Count);
    for I:=0 to Reverse.Count-1 do Path[I]:=Nodes[Reverse[Reverse.Count-1-I]].P;
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

function ReconstructReference(Glyph: TWritingGlyph; out Info: TReferenceFitInfo; out Targets: TPaths; Align: Boolean; Enhanced: Integer=0): Boolean;
var Reference: TStrokeReference; Nodes: TNodes; Paths: TArray<TStroke>;
  I,J,K,Hit,Missed,Total,Repeated,Head,Tail: Integer; RLo,RHi,GLo,GHi,P: TPointF;
  Covered,Visited: TArray<Boolean>; Queue: TArray<Integer>; AnyCovered: Boolean;
  Candidate: TPoints; Best,Average,Worst: Double; Edges: TDictionary<Int64,Integer>; Key: Int64;
  function NodeNumber(const Q: TPointF): Integer;
  begin Result:=Round(Q.Y)*Glyph.Width+Round(Q.X) end;
begin
  Result:=False; Targets:=nil; Info:=Default(TReferenceFitInfo); Info.Reason:='no-reference';
  if (Length(Glyph.Character)<>1) or Glyph.Missing or Glyph.Learned or
    not FindStrokeReference(Ord(Glyph.Character[1]),Reference) then Exit;
  Info.Available:=True; Info.Reason:='shape-mismatch';
  if (Glyph.Width<2) or (Glyph.Height<2) or (Length(Glyph.Mask)<>Glyph.Width*Glyph.Height) then Exit;
  Nodes:=BuildGraph(Glyph,Info.RecoveredComponents); if (Length(Nodes)<2) or (Length(Nodes)>4096) then Exit;
  if Enhanced>0 then Info.RepairedEdges:=RepairGraphNeighbours(Glyph,Nodes);
  RLo:=PointF(1E9,1E9); RHi:=PointF(-1E9,-1E9); GLo:=RLo; GHi:=RHi;
  for I:=0 to High(Reference.Strokes) do for P in Reference.Strokes[I].Points do
  begin RLo.X:=Min(RLo.X,P.X); RLo.Y:=Min(RLo.Y,P.Y); RHi.X:=Max(RHi.X,P.X); RHi.Y:=Max(RHi.Y,P.Y) end;
  for I:=0 to High(Nodes) do
  begin P:=Nodes[I].P; GLo.X:=Min(GLo.X,P.X); GLo.Y:=Min(GLo.Y,P.Y); GHi.X:=Max(GHi.X,P.X); GHi.Y:=Max(GHi.Y,P.Y) end;
  SetLength(Targets,Length(Reference.Strokes)); SetLength(Paths,Length(Targets));
  for I:=0 to High(Targets) do
  begin
    Candidate:=Copy(Reference.Strokes[I].Points);
    for J:=0 to High(Candidate) do
      Candidate[J]:=PointF(GLo.X+(Candidate[J].X-RLo.X)*(GHi.X-GLo.X)/Max(0.001,RHi.X-RLo.X),
        GLo.Y+(Candidate[J].Y-RLo.Y)*(GHi.Y-GLo.Y)/Max(0.001,RHi.Y-RLo.Y));
    Targets[I]:=Samples(Candidate,EnsureRange(Ceil(PathLength(Candidate)/2.5)+1,12,100));
  end;
  if Enhanced=3 then
  begin
    if not AlignReferenceComponents(Nodes,Targets) then begin Info.Reason:='component-mismatch'; Exit end;
    Info.AdaptedGuide:=True;
  end
  else if Align then AlignTargets(Glyph,Nodes,Targets);
  if Enhanced=2 then
  begin
    if not AdaptGuides(Nodes,Targets) then begin Info.Reason:='guide-mismatch'; Exit end;
    Info.AdaptedGuide:=True;
  end;
  for I:=0 to High(Targets) do
  begin
    if not TraceReference(Nodes,Targets[I],Candidate) then begin Info.Reason:='trace-mismatch-'+IntToStr(I+1); Exit end;
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
    Covered[K]:=Best<=3.5; if not Covered[K] then Inc(Missed);
  end;
  Info.Coverage:=1-Missed/Length(Nodes);
  if Info.Coverage<0.92 then begin Info.Reason:='uncovered-shape'; Exit end;
  SetLength(Visited,Length(Nodes)); SetLength(Queue,Length(Nodes));
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
  Total:=0; Repeated:=0; Edges:=TDictionary<Int64,Integer>.Create;
  try
    for I:=0 to High(Paths) do for J:=1 to High(Paths[I].Points) do
    begin
      K:=NodeNumber(Paths[I].Points[J-1]); Hit:=NodeNumber(Paths[I].Points[J]); if K=Hit then Continue;
      Key:=Int64(Min(K,Hit))*Int64(Glyph.Width*Glyph.Height)+Max(K,Hit); Inc(Total);
      if Edges.ContainsKey(Key) then Inc(Repeated) else Edges.Add(Key,1);
    end;
  finally Edges.Free end;
  if Repeated>Max(6,Total*0.08) then begin Info.Reason:='ambiguous-overlap'; Exit end;
  Info.BeforeError:=OrderedError(Targets,Glyph.Strokes); Info.AfterError:=OrderedError(Targets,Paths);
  if (Info.AfterError>8) or (Info.AfterError+0.75>=Info.BeforeError) then begin Info.Reason:='no-clear-improvement'; Exit end;
  Glyph.Strokes:=Paths; Glyph.ReferenceOrderOnly:=False;
  Info.Accepted:=True; Info.Mode:='paths'; Info.Reason:='accepted'; Result:=True;
end;

function TryApplyStrokeReference(Glyph: TWritingGlyph; out Info: TReferenceFitInfo): Boolean;
var Targets,AlignedTargets: TPaths; Improvement: Double; AlignedInfo: TReferenceFitInfo;
begin
  Result:=ReconstructReference(Glyph,Info,Targets,False); if Result or not Info.Available then Exit;
  Result:=ReconstructReference(Glyph,AlignedInfo,AlignedTargets,True);
  if Result then begin Info:=AlignedInfo; Exit end;
  if ((Length(Targets)>0) and ApplyReferenceOrder(Glyph,Targets,Improvement,Info.OrderReason)) or
     ((Length(AlignedTargets)>0) and ApplyReferenceOrder(Glyph,AlignedTargets,Improvement,Info.OrderReason)) then
  begin
    Info.Accepted:=True; Info.Mode:='order'; Info.Reason:='reference-order'; Info.Coverage:=1;
    Info.OrderImprovement:=Improvement; Glyph.ReferenceOrderOnly:=True; Result:=True;
    Exit;
  end;
  // 従来の採用結果を維持し、それでも不採用の字だけ接続復元と局所対応を試す。
  Result:=ReconstructReference(Glyph,AlignedInfo,AlignedTargets,True,1);
  if not Result then Result:=ReconstructReference(Glyph,AlignedInfo,AlignedTargets,True,3);
  if not Result then Result:=ReconstructReference(Glyph,AlignedInfo,AlignedTargets,True,2);
  if Result then Info:=AlignedInfo;
end;

end.
