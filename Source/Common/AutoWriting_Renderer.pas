unit AutoWriting_Renderer;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 文字配置・距離ベースのタイムライン・RGBA描画をプレビューと本体で共有する。
// すべて時刻から直接評価する。出力拡大率は距離・完了時刻に影響しない。

interface

uses System.Types, AutoWriting_Types, AutoWriting_Fonts;

type
  TPlacedGlyph = record
    // Glyphはフォントエンジンから借用する。配置の再構築前に参照を破棄する。
    Glyph: TWritingGlyph;
    X,Y,Scale,StartDistance,EndDistance: Double;
  end;
  TPenSegment = record
    A,B: TPointF;
    StartDistance,Length: Double;
    Down: Boolean;
  end;
  TWritingRenderer = class
  private
    type TCharacterMove = record
      StartDistance, Length, PreviousMoveDistance: Double;
    end;
  private
    FEngine: TWritingFontEngine;
    FKey: string;
    FRevision: Integer;
    FGlyphs: TArray<TPlacedGlyph>;
    FSegments: TArray<TPenSegment>;
    FBounds: TRectF;
    FTotalDistance, FTotalMoveDistance: Double;
    FCharacterMoves: TArray<TCharacterMove>;
    procedure BuildLayout(const S: TWritingSettings);
    function DistanceAtTime(Time: Double; const S: TWritingSettings): Double;
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(const S: TWritingSettings);
    // 画と画間の移動、文字間の移動を指定された速度で計算する（秒）。
    function Duration(const S: TWritingSettings): Double;
    // Input=nilで透明背景。入力は借用し、Outputはレンダラー呼出側が所有する。
    procedure Render(const Input: TWritingPixels; Width,Height: Integer;
      Time: Double; const S: TWritingSettings; var Output: TWritingPixels);
    // 拡大前の座標と持上げ割合0..1を返す。筆記完了後はFalse。
    function PenAt(Distance: Double; out Position: TPointF; out Lift: Double): Boolean;
    property Engine: TWritingFontEngine read FEngine;
    property TotalDistance: Double read FTotalDistance;
    property Bounds: TRectF read FBounds;
    property PlacedGlyphs: TArray<TPlacedGlyph> read FGlyphs;
  end;

{$IFDEF AW_PROFILE}
type
  TWritingRenderProfile = record
    Frames,LayoutTicks,ClearTicks,InkTicks,ShadowTicks,PenTicks,PenPixels,ShadowPixels: Int64;
  end;
// 検査ビルドだけの呼出し元所有バッファへ、現在スレッドの集計値を返す。
procedure ResetWritingRenderProfile; cdecl;
procedure ReadWritingRenderProfile(out Profile: TWritingRenderProfile); cdecl;
procedure SetWritingProfileFullScan(Enabled: Integer); cdecl;
{$ENDIF}

implementation

uses System.SysUtils, System.Math, System.Generics.Collections, AviUtl2FilterTypes, AutoWriting_Learning
  {$IFDEF AW_PROFILE}, System.Diagnostics{$ENDIF};

{$IFDEF AW_PROFILE}
threadvar RenderProfile: TWritingRenderProfile;
  ProfileFullScan: Boolean;
procedure ResetWritingRenderProfile; cdecl;
begin FillChar(RenderProfile,SizeOf(RenderProfile),0) end;
procedure ReadWritingRenderProfile(out Profile: TWritingRenderProfile); cdecl;
begin Profile:=RenderProfile end;
procedure SetWritingProfileFullScan(Enabled: Integer); cdecl;
begin ProfileFullScan:=Enabled<>0 end;
{$ENDIF}

constructor TWritingRenderer.Create;
begin inherited; FEngine:=TWritingFontEngine.Create; FRevision:=-1 end;

destructor TWritingRenderer.Destroy;
begin FEngine.Free; inherited end;

procedure TWritingRenderer.Prepare(const S: TWritingSettings);
var Key: string; LayoutSettings: TWritingSettings;
begin
  // 速度は経路距離から時刻を求める段階で使い、組版キー（詳細JSON）へ含めない。
  // 筆記具のサイズ・角度・光源もフレームごとに変えられる。
  LayoutSettings:=S; LayoutSettings.PenSize:=1; LayoutSettings.PenAngle:=0; LayoutSettings.LightX:=0; LayoutSettings.LightY:=0;
  Key:=S.Text+'|'+SettingsJSON(LayoutSettings);
  if (Key=FKey) and (FRevision=LearningRevision) then Exit;
  FKey:=''; FRevision:=-1;
  FGlyphs:=nil; FSegments:=nil; FCharacterMoves:=nil; FEngine.Configure(S); BuildLayout(S);
  FKey:=Key; FRevision:=LearningRevision;
end;

procedure TWritingRenderer.BuildLayout(const S: TWritingSettings);
var Characters: TArray<string>; C: string; G: TWritingGlyph; PG: TPlacedGlyph;
  Placed: TList<TPlacedGlyph>; Segments: TList<TPenSegment>; Seg: TPenSegment;
  CharacterMoves: TList<TCharacterMove>; CharacterMove: TCharacterMove;
  CursorX,CursorY,Size,Ratio,Cell,LocalStart,StrokeStart,MoveStart,PosX,PosY: Double;
  Last,A,B: TPointF; HavePen,HaveBounds,GlyphHasPen: Boolean; I,J: Integer;
  procedure AddSegment(const P1,P2: TPointF; Down: Boolean; MinLength: Double=0);
  begin
    Seg.A:=P1; Seg.B:=P2; Seg.Length:=Max(MinLength,Distance(P1,P2));
    Seg.StartDistance:=FTotalDistance; Seg.Down:=Down;
    if Seg.Length>0 then begin Segments.Add(Seg); FTotalDistance:=FTotalDistance+Seg.Length end;
  end;
begin
  Placed:=nil; Segments:=nil; CharacterMoves:=nil;
  try
    Placed:=TList<TPlacedGlyph>.Create; Segments:=TList<TPenSegment>.Create;
    CharacterMoves:=TList<TCharacterMove>.Create;
    FTotalDistance:=0; FTotalMoveDistance:=0; FBounds:=TRectF.Empty; CursorX:=0; CursorY:=0;
    HavePen:=False; HaveBounds:=False; Last:=PointF(0,0);
    Size:=SafeNumber(S.FontSize,80,12,256); Characters:=UnicodeCharacters(S.Text);
    for C in Characters do
    begin
      if C=#10 then
      begin
        if S.Vertical then begin CursorX:=CursorX-Size*(1+S.LineGap); CursorY:=0 end
        else begin CursorX:=0; CursorY:=CursorY+Size*(1+S.LineGap) end;
        Continue;
      end;
      G:=FEngine.Glyph(C); Ratio:=S.Ratios[CharacterKind(C)];
      PG:=Default(TPlacedGlyph); PG.Glyph:=G; PG.Scale:=Size*Ratio/AW_EM;
      Cell:=G.Advance*PG.Scale;
      PG.X:=CursorX+G.OriginX*PG.Scale;
      PG.Y:=CursorY+Size*0.88-G.OriginY*PG.Scale;
      if S.Vertical then
      begin
        PG.X:=CursorX+(Size-Cell)/2+G.OriginX*PG.Scale;
        PG.Y:=CursorY+Size*0.88-G.OriginY*PG.Scale;
        if (C='。') or (C='、') or (C='，') or (C='．') then
        begin PG.X:=PG.X+Size*0.5; PG.Y:=PG.Y-Size*0.55 end;
      end;
      if (G.Width>0) and (G.Height>0) then
      begin
        PosX:=PG.X+G.Width*PG.Scale; PosY:=PG.Y+G.Height*PG.Scale;
        if not HaveBounds then
        begin FBounds:=RectF(PG.X,PG.Y,PosX,PosY); HaveBounds:=True end
        else begin
          FBounds.Left:=Min(FBounds.Left,PG.X); FBounds.Top:=Min(FBounds.Top,PG.Y);
          FBounds.Right:=Max(FBounds.Right,PosX); FBounds.Bottom:=Max(FBounds.Bottom,PosY);
        end;
      end;
      LocalStart:=FTotalDistance; GlyphHasPen:=False;
      for I:=0 to High(G.Strokes) do
      begin
        if Length(G.Strokes[I].Points)=0 then Continue;
        A:=G.Strokes[I].Points[0]; A:=PointF(PG.X+A.X*PG.Scale,PG.Y+A.Y*PG.Scale);
        if HavePen then
        begin
          MoveStart:=FTotalDistance;
          AddSegment(Last,A,False);
          if not GlyphHasPen and (FTotalDistance>MoveStart) then
          begin
            CharacterMove.StartDistance:=MoveStart;
            CharacterMove.Length:=FTotalDistance-MoveStart;
            CharacterMove.PreviousMoveDistance:=FTotalMoveDistance;
            CharacterMoves.Add(CharacterMove);
            FTotalMoveDistance:=FTotalMoveDistance+CharacterMove.Length;
          end;
        end;
        if not GlyphHasPen then LocalStart:=FTotalDistance;
        StrokeStart:=FTotalDistance;
        for J:=1 to High(G.Strokes[I].Points) do
        begin
          B:=G.Strokes[I].Points[J]; B:=PointF(PG.X+B.X*PG.Scale,PG.Y+B.Y*PG.Scale);
          AddSegment(A,B,True); A:=B;
        end;
        // 点も一定距離を使う。ゼロ長画で時間が消えないようにする。
        if FTotalDistance-StrokeStart<G.Strokes[I].Length*PG.Scale then
          AddSegment(A,A,True,G.Strokes[I].Length*PG.Scale-(FTotalDistance-StrokeStart));
        Last:=A; HavePen:=True; GlyphHasPen:=True;
      end;
      PG.StartDistance:=LocalStart; PG.EndDistance:=FTotalDistance; Placed.Add(PG);
      if S.Vertical then CursorY:=CursorY+Size+Size*S.LetterGap
      else CursorX:=CursorX+Cell+Size*S.LetterGap;
    end;
    FGlyphs:=Placed.ToArray; FSegments:=Segments.ToArray; FCharacterMoves:=CharacterMoves.ToArray;
  finally CharacterMoves.Free; Segments.Free; Placed.Free end;
end;

function WritingMoveSpeed(const S: TWritingSettings; Speed: Double): Double;
begin
  Result:=SafeNumber(S.MoveSpeed,0,0,10000);
  if Result=0 then Result:=Speed else Result:=Max(1,Result);
end;

function TWritingRenderer.Duration(const S: TWritingSettings): Double;
var Speed, MoveSpeed: Double;
begin
  Prepare(S); Speed:=SafeNumber(S.Speed,240,1,10000); MoveSpeed:=WritingMoveSpeed(S,Speed);
  if (Speed=MoveSpeed) or (FTotalMoveDistance=0) then Exit(FTotalDistance/Speed);
  Result:=(FTotalDistance-FTotalMoveDistance)/Speed+FTotalMoveDistance/MoveSpeed;
end;

function TWritingRenderer.DistanceAtTime(Time: Double; const S: TWritingSettings): Double;
var Speed, MoveSpeed, Ratio, Extra, Start, D: Double; L,R,M: Integer; Gap: TCharacterMove;
begin
  Speed:=SafeNumber(S.Speed,240,1,10000); D:=SafeNumber(Time,0,0,1E12)*Speed;
  MoveSpeed:=WritingMoveSpeed(S,Speed);
  if (MoveSpeed=Speed) or (Length(FCharacterMoves)=0) then Exit(D);

  // 秒を筆記速度相当の距離に換算し、文字間移動の分だけ補正して元の経路距離へ戻す。
  Ratio:=Speed/MoveSpeed; Extra:=Ratio-1;
  L:=0; R:=Length(FCharacterMoves);
  while L<R do
  begin
    M:=(L+R) div 2; Gap:=FCharacterMoves[M];
    if Gap.StartDistance+Gap.PreviousMoveDistance*Extra+Gap.Length*Ratio<=D then L:=M+1 else R:=M;
  end;
  if L=Length(FCharacterMoves) then Exit(D-FTotalMoveDistance*Extra);
  Gap:=FCharacterMoves[L]; Start:=Gap.StartDistance+Gap.PreviousMoveDistance*Extra;
  if D<Start then Result:=D-Gap.PreviousMoveDistance*Extra
  else Result:=Gap.StartDistance+(D-Start)/Ratio;
end;

function TWritingRenderer.PenAt(Distance: Double; out Position: TPointF; out Lift: Double): Boolean;
var L,R,M: Integer; T: Double; Seg: TPenSegment;
begin
  Result:=(Distance>=0) and (Distance<FTotalDistance) and (Length(FSegments)>0);
  Position:=PointF(0,0); Lift:=0; if not Result then Exit;
  L:=0; R:=High(FSegments);
  while L<R do
  begin
    M:=(L+R) div 2;
    if FSegments[M].StartDistance+FSegments[M].Length<=Distance then L:=M+1 else R:=M;
  end;
  Seg:=FSegments[L]; T:=EnsureRange((Distance-Seg.StartDistance)/Max(1E-9,Seg.Length),0.0,1.0);
  Position:=PointF(Seg.A.X+(Seg.B.X-Seg.A.X)*T,Seg.A.Y+(Seg.B.Y-Seg.A.Y)*T);
  if not Seg.Down then Lift:=Sin(Pi*T);
end;

procedure Blend(var Dest: TPIXEL_RGBA; Color: Cardinal; Alpha: Integer);
var DA,OutA: Integer;
begin
  Alpha:=EnsureRange(Alpha,0,255); if Alpha=0 then Exit;
  DA:=(Integer(Dest.A)*(255-Alpha)+127) div 255; OutA:=Alpha+DA;
  Dest.R:=(Integer((Color shr 16) and 255)*Alpha+Integer(Dest.R)*DA+OutA div 2) div OutA;
  Dest.G:=(Integer((Color shr 8) and 255)*Alpha+Integer(Dest.G)*DA+OutA div 2) div OutA;
  Dest.B:=(Integer(Color and 255)*Alpha+Integer(Dest.B)*DA+OutA div 2) div OutA;
  Dest.A:=OutA;
end;

function PenLength(Pen: TPenKind): Double;
begin if Pen=pkQuill then Result:=124 else Result:=78 end;

function PenMaxWidth(Pen: TPenKind): Double;
begin if Pen=pkQuill then Result:=24 else Result:=5.5 end;

function PenCenterAt(Pen: TPenKind; U: Double): Double;
var T: Double;
begin
  Result:=0; if (Pen<>pkQuill) or (U<24) then Exit;
  T:=EnsureRange((U-24)/100,0.0,1.0); Result:=-6*T*T-4*Sin(Pi*T);
end;

function PenWidthAt(Pen: TPenKind; U: Double): Double;
begin
  case Pen of
    pkPencil: Result:=Min(4,U*0.4);
    pkBallpoint: Result:=Min(3.5,0.6+U*0.3);
    pkFountain: if U<14 then Result:=Min(U*0.55,(18-U)*0.55) else Result:=4.5;
    pkBrush: if U<22 then Result:=Sin(U/28*Pi)*5.5 else Result:=2.8;
    pkQuill: if U<24 then Result:=Min(1.4,0.15+U*0.25)
      else Result:=0.4+16*Power(Max(0.0,Sin(Pi*EnsureRange((U-24)/100,0.0,1.0))),0.85);
    else Result:=4;
  end;
end;

type
  TQuillSection = record Center,Width,Rib: Double end;
const QUILL_SECTIONS=992; // 124pxを1/8px刻みで保持。角度や拡大率には依存しない。
var QuillSections: array[0..QUILL_SECTIONS] of TQuillSection;

procedure InitializeQuillSections;
var I: Integer; U,T: Double;
begin
  for I:=0 to QUILL_SECTIONS do begin
    U:=I/8; T:=Max(0.0,(U-24)/100);
    QuillSections[I].Center:=PenCenterAt(pkQuill,U);
    QuillSections[I].Width:=PenWidthAt(pkQuill,U); QuillSections[I].Rib:=-6*T*T;
  end;
end;

// 初期化後は不変の表を補間する。画素ループ内でSin/Powerを実行しない。
function QuillSectionAt(U: Double): TQuillSection; inline;
var I: Integer; F: Double;
begin
  if U<24 then begin Result.Center:=0; Result.Width:=0.15+U*0.25;
    if Result.Width>1.4 then Result.Width:=1.4; Result.Rib:=0; Exit end;
  F:=U*8; if F<0 then F:=0 else if F>QUILL_SECTIONS then F:=QUILL_SECTIONS;
  I:=Trunc(F); if I>=QUILL_SECTIONS then I:=QUILL_SECTIONS-1; F:=F-I;
  Result.Center:=QuillSections[I].Center+(QuillSections[I+1].Center-QuillSections[I].Center)*F;
  Result.Width:=QuillSections[I].Width+(QuillSections[I+1].Width-QuillSections[I].Width)*F;
  Result.Rib:=QuillSections[I].Rib+(QuillSections[I+1].Rib-QuillSections[I].Rib)*F;
end;

// GroundTipは紙面上のペン先。軸の各断面の高さを光源方向へ平行投影する。
// ペン先の接触時は影も同一点。軸の後端ほど高く、投影距離とぼかしが増える。
// 光源XYはペン先基準、高さ200固定の方向光。画面上ではY正が下。
procedure DrawPenShadow(var Output: TWritingPixels; W,H: Integer; const GroundTip: TPointF;
  const S: TWritingSettings; GlobalScale,Opacity,Lift: Double);
const ShaftRise=0.55;
var TipHeight,Height,Scale,PenSize,Angle,CS,SN,LX,LY,Blur,Padding,Fade,U,T,PX,PY,D,Alpha: Double;
  AX,AY,AxisLength,UnitX,UnitY,SideFactor,Width,Along,Across,Len: Double;
  Tip,Back: TPointF; X,Y,X0,X1,Y0,Y1: Integer; Section: TQuillSection;
begin
  TipHeight:=SafeNumber(S.LiftHeight,16,0,80)*Lift;
  PenSize:=SafeNumber(S.PenSize,1,0.3,3); Scale:=Max(0.02,PenSize*GlobalScale);
  Angle:=(SafeNumber(S.PenAngle,35,-180,180)-90)*Pi/180; CS:=Cos(Angle); SN:=Sin(Angle);
  LX:=SafeNumber(S.LightX,-100,-400,400)/200; LY:=SafeNumber(S.LightY,-100,-400,400)/200;
  Tip:=PointF(GroundTip.X-LX*TipHeight*GlobalScale,GroundTip.Y-LY*TipHeight*GlobalScale);
  Len:=PenLength(S.Pen); AX:=Len*Scale*(CS-ShaftRise*LX); AY:=Len*Scale*(SN+ShaftRise*(1-LY));
  Back:=PointF(Tip.X+AX,Tip.Y+AY); AxisLength:=Hypot(AX,AY);
  UnitX:=1; UnitY:=0; if AxisLength>1E-6 then begin UnitX:=AX/AxisLength; UnitY:=AY/AxisLength end;
  SideFactor:=UnitX*CS+UnitY*SN;
  Blur:=Max(0.25,(0.35+(TipHeight+Len*PenSize*ShaftRise)*0.05)*GlobalScale);
  Padding:=PenMaxWidth(S.Pen)*Scale+Blur*3.5;
  X0:=Max(0,Floor(Min(Tip.X,Back.X)-Padding)); X1:=Min(W-1,Ceil(Max(Tip.X,Back.X)+Padding));
  Y0:=Max(0,Floor(Min(Tip.Y,Back.Y)-Padding)); Y1:=Min(H-1,Ceil(Max(Tip.Y,Back.Y)+Padding));
  {$IFDEF AW_PROFILE}Inc(RenderProfile.ShadowPixels,Int64(Max(0,X1-X0+1))*Max(0,Y1-Y0+1));{$ENDIF}
  for Y:=Y0 to Y1 do for X:=X0 to X1 do
  begin
    PX:=X+0.5-Tip.X; PY:=Y+0.5-Tip.Y;
    Along:=PX*UnitX+PY*UnitY;
    T:=1; if AxisLength>1E-6 then T:=EnsureRange(Along/AxisLength,0.0,1.0);
    U:=T*Len; Height:=TipHeight+U*PenSize*ShaftRise;
    if S.Pen=pkQuill then begin Section:=QuillSectionAt(U);
      Across:=Abs(-PX*UnitY+PY*UnitX-Section.Center*Scale*SideFactor);
      Width:=Section.Width*Scale*Abs(SideFactor);
    end else begin
      Across:=Abs(-PX*UnitY+PY*UnitX-PenCenterAt(S.Pen,U)*Scale*SideFactor);
      Width:=PenWidthAt(S.Pen,U)*Scale*Abs(SideFactor);
    end;
    if AxisLength<=1E-6 then Width:=PenMaxWidth(S.Pen)*Scale;
    if (S.Pen=pkQuill) and (Along>=0) and (Along<=AxisLength) then D:=Across-Width
    else D:=Hypot(Along-T*AxisLength,Across)-Width;
    Blur:=Max(0.25,(0.35+Height*0.05)*GlobalScale);
    if D>Blur*3.5 then Continue;
    Fade:=Min(1.0,Height/3); Fade:=Fade*Fade*(3-2*Fade);
    Alpha:=0.28*Fade*Opacity/(1+Height*0.012)/(1+Exp(EnsureRange(D*1.6/Blur,-40.0,40.0)));
    Blend(Output[Y*W+X],$000000,Round(Alpha*255));
  end;
end;

procedure DrawPen(var Output: TWritingPixels; W,H: Integer; const Tip: TPointF;
  const S: TWritingSettings; GlobalScale,Opacity,Lift: Double);
var X,Y,X0,Y0,X1,Y1,SX,SY,Hits: Integer;
  Angle,CS,SN,Scale,Len,Radius,U,V,PX,PY,Width,Q,Rib,Padding: Double; Color,SampleColor: Cardinal;
  RSum,GSum,BSum,RowX0,RowX1: Integer; Back: TPointF; Section: TQuillSection;
  Margin,DY,LowX,HighX,A,B: Double;
begin
  Angle:=(SafeNumber(S.PenAngle,35,-180,180)-90)*Pi/180; CS:=Cos(Angle); SN:=Sin(Angle);
  Scale:=Max(0.02,SafeNumber(S.PenSize,1,0.3,3)*GlobalScale); Len:=PenLength(S.Pen); Radius:=Len*Scale+3;
  X0:=Max(0,Floor(Tip.X-Radius)); X1:=Min(W-1,Ceil(Tip.X+Radius));
  Y0:=Max(0,Floor(Tip.Y-Radius)); Y1:=Min(H-1,Ceil(Tip.Y+Radius));
  if (S.Pen=pkQuill) {$IFDEF AW_PROFILE}and not ProfileFullScan{$ENDIF} then begin
    Back:=PointF(Tip.X+Len*Scale*CS,Tip.Y+Len*Scale*SN); Padding:=PenMaxWidth(S.Pen)*Scale+1;
    X0:=Max(0,Floor(Min(Tip.X,Back.X)-Padding)); X1:=Min(W-1,Ceil(Max(Tip.X,Back.X)+Padding));
    Y0:=Max(0,Floor(Min(Tip.Y,Back.Y)-Padding)); Y1:=Min(H-1,Ceil(Max(Tip.Y,Back.Y)+Padding));
  end;
  Margin:=0.25*(Abs(CS)+Abs(SN));
  for Y:=Y0 to Y1 do
  begin
    RowX0:=X0; RowX1:=X1;
    // 4サンプルのいずれも届かない、回転した羽の外接矩形の外側は走査しない。
    if (S.Pen=pkQuill) {$IFDEF AW_PROFILE}and not ProfileFullScan{$ENDIF} then begin
      DY:=Y+0.5-Tip.Y; LowX:=X0+0.5-Tip.X; HighX:=X1+0.5-Tip.X;
      if Abs(CS)>1E-9 then begin
        A:=(-Margin-DY*SN)/CS; B:=(Len*Scale+Margin-DY*SN)/CS;
        LowX:=Max(LowX,Min(A,B)); HighX:=Min(HighX,Max(A,B));
      end else if (DY*SN< -Margin) or (DY*SN>Len*Scale+Margin) then Continue;
      if Abs(SN)>1E-9 then begin
        A:=(-PenMaxWidth(S.Pen)*Scale-Margin-DY*CS)/(-SN);
        B:=(PenMaxWidth(S.Pen)*Scale+Margin-DY*CS)/(-SN);
        LowX:=Max(LowX,Min(A,B)); HighX:=Min(HighX,Max(A,B));
      end else if Abs(DY*CS)>PenMaxWidth(S.Pen)*Scale+Margin then Continue;
      RowX0:=Max(X0,Floor(LowX+Tip.X-0.5)); RowX1:=Min(X1,Ceil(HighX+Tip.X-0.5));
    end;
    {$IFDEF AW_PROFILE}Inc(RenderProfile.PenPixels,Max(0,RowX1-RowX0+1));{$ENDIF}
    for X:=RowX0 to RowX1 do
  begin
    Hits:=0; RSum:=0; GSum:=0; BSum:=0;
    for SY:=0 to 1 do for SX:=0 to 1 do
    begin
      PX:=X+0.25+SX*0.5-Tip.X; PY:=Y+0.25+SY*0.5-Tip.Y;
      U:=(PX*CS+PY*SN)/Scale; V:=(-PX*SN+PY*CS)/Scale;
      if (U<0) or (U>Len) then Continue;
      if S.Pen=pkQuill then begin Section:=QuillSectionAt(U); Width:=Section.Width; Q:=V-Section.Center end
      else begin Width:=PenWidthAt(S.Pen,U); Q:=V-PenCenterAt(S.Pen,U) end;
      if Abs(Q)>Width then Continue;
      SampleColor:=$2C3554;
      case S.Pen of
        pkPencil: begin
          SampleColor:=$E9B949;
          if U<11 then SampleColor:=$CFAB7A; if U<3 then SampleColor:=$303034;
          if U>70 then SampleColor:=$CB777D;
        end;
        pkBallpoint: begin
          SampleColor:=$34679C;
          if U<8 then SampleColor:=$A6AFBC; if U<2 then SampleColor:=$202028;
          if (U>22) and (V< -1.5) then SampleColor:=$82A8CE;
        end;
        pkFountain: begin
          if U<14 then SampleColor:=$D5AE57 else SampleColor:=$333047;
          if U<2 then SampleColor:=$202028;
          if (U>18) and (U<21) then SampleColor:=$CDB477;
        end;
        pkBrush: begin
          if U<22 then SampleColor:=$252026 else SampleColor:=$96683D;
        end;
        pkQuill: begin
          if U<24 then begin
            SampleColor:=$C8B38B; if Abs(V)>0.9 then SampleColor:=$9E8358;
            if U<3 then SampleColor:=$514136;
          end else begin
            Rib:=V-Section.Rib;
            SampleColor:=$F5EEDB; if Rib<0 then SampleColor:=$FCF8EB;
            if Abs(Frac((U-Abs(Rib)*1.1)/6)-0.5)<0.08 then SampleColor:=$D6C9AA;
            if Abs(Q)>Width-0.65 then SampleColor:=$AE9E7D;
            if Abs(Rib)<0.65 then SampleColor:=$B59A6C;
            if (U>36) and (Abs(Q)>Width*0.72) and (Frac((U-Abs(Rib)*0.8)/13)<0.09) then Continue;
          end;
        end;
      end;
      Inc(Hits); Inc(RSum,(SampleColor shr 16) and 255);
      Inc(GSum,(SampleColor shr 8) and 255); Inc(BSum,SampleColor and 255);
    end;
    if Hits=0 then Continue;
    Color:=(Cardinal(RSum div Hits) shl 16) or (Cardinal(GSum div Hits) shl 8) or Cardinal(BSum div Hits);
    Blend(Output[Y*W+X],Color,Round(Hits*255*Opacity*(1-Lift*0.15)/4));
  end;
  end;
end;

procedure TWritingRenderer.Render(const Input: TWritingPixels; Width,Height: Integer;
  Time: Double; const S: TWritingSettings; var Output: TWritingPixels);
var GlobalScale,OffsetX,OffsetY,Opacity,D,LocalD,Scale,PX,PY,FX,FY,Alpha,WX,WY: Double;
  PG: TPlacedGlyph; G: TWritingGlyph; X,Y,X0,Y0,X1,Y1,IX,IY,SX,SY,MX,MY,Index: Integer;
  Complete: Boolean; Pen: TPointF; Lift: Double;
  {$IFDEF AW_PROFILE}Stamp: Int64;{$ENDIF}
begin
  if (Width<=0) or (Height<=0) or (Width>8192) or (Height>8192) or
    (Int64(Width)*Height>AW_MAX_PIXELS) then raise EArgumentException.Create('Invalid output dimensions');
  {$IFDEF AW_PROFILE}Inc(RenderProfile.Frames); Stamp:=TStopwatch.GetTimeStamp;{$ENDIF}
  Prepare(S);
  {$IFDEF AW_PROFILE}Inc(RenderProfile.LayoutTicks,TStopwatch.GetTimeStamp-Stamp); Stamp:=TStopwatch.GetTimeStamp;{$ENDIF}
  SetLength(Output,Width*Height);
  if Length(Input)=Length(Output) then Move(Input[0],Output[0],Length(Output)*SizeOf(TPIXEL_RGBA))
  else FillChar(Output[0],Length(Output)*SizeOf(TPIXEL_RGBA),0);
  {$IFDEF AW_PROFILE}Inc(RenderProfile.ClearTicks,TStopwatch.GetTimeStamp-Stamp);{$ENDIF}
  GlobalScale:=SafeNumber(S.Scale,100,0,1000)/100;
  Opacity:=1-SafeNumber(S.Transparency,0,0,100)/100;
  if (GlobalScale<=0) or (Opacity<=0) then Exit;
  D:=DistanceAtTime(Time,S);
  OffsetX:=Width/2+S.X-(FBounds.Left+FBounds.Right)/2*GlobalScale;
  OffsetY:=Height/2+S.Y-(FBounds.Top+FBounds.Bottom)/2*GlobalScale;
  {$IFDEF AW_PROFILE}Stamp:=TStopwatch.GetTimeStamp;{$ENDIF}
  for PG in FGlyphs do
  begin
    G:=PG.Glyph; if (Length(G.Mask)=0) or (D<=PG.StartDistance) then Continue;
    Complete:=D>=PG.EndDistance; LocalD:=(D-PG.StartDistance)/PG.Scale;
    Scale:=PG.Scale*GlobalScale; PX:=OffsetX+PG.X*GlobalScale; PY:=OffsetY+PG.Y*GlobalScale;
    X0:=Max(0,Floor(PX-1)); Y0:=Max(0,Floor(PY-1));
    X1:=Min(Width-1,Ceil(PX+G.Width*Scale+1)); Y1:=Min(Height-1,Ceil(PY+G.Height*Scale+1));
    for Y:=Y0 to Y1 do for X:=X0 to X1 do
    begin
      FX:=(X+0.5-PX)/Scale-0.5; FY:=(Y+0.5-PY)/Scale-0.5;
      IX:=Floor(FX); IY:=Floor(FY); FX:=FX-IX; FY:=FY-IY; Alpha:=0;
      for SY:=0 to 1 do for SX:=0 to 1 do
      begin
        MX:=IX+SX; MY:=IY+SY;
        if (MX<0) or (MY<0) or (MX>=G.Width) or (MY>=G.Height) then Continue;
        Index:=MY*G.Width+MX;
        if not Complete and (G.Reveal[Index]>LocalD) then Continue;
        if SX=0 then WX:=1-FX else WX:=FX;
        if SY=0 then WY:=1-FY else WY:=FY;
        Alpha:=Alpha+G.Mask[Index]*WX*WY;
      end;
      if Alpha>0 then Blend(Output[Y*Width+X],S.InkColor,Round(Alpha*Opacity));
    end;
  end;
  {$IFDEF AW_PROFILE}Inc(RenderProfile.InkTicks,TStopwatch.GetTimeStamp-Stamp);{$ENDIF}
  if S.ShowPen and (S.Pen<>pkNone) and PenAt(D,Pen,Lift) then
  begin
    Pen:=PointF(OffsetX+Pen.X*GlobalScale,OffsetY+Pen.Y*GlobalScale);
    {$IFDEF AW_PROFILE}Stamp:=TStopwatch.GetTimeStamp;{$ENDIF}
    DrawPenShadow(Output,Width,Height,Pen,S,GlobalScale,Opacity,Lift);
    {$IFDEF AW_PROFILE}Inc(RenderProfile.ShadowTicks,TStopwatch.GetTimeStamp-Stamp);{$ENDIF}
    Pen.Y:=Pen.Y-SafeNumber(S.LiftHeight,16,0,80)*Lift*GlobalScale;
    {$IFDEF AW_PROFILE}Stamp:=TStopwatch.GetTimeStamp;{$ENDIF}
    DrawPen(Output,Width,Height,Pen,S,GlobalScale,Opacity,Lift);
    {$IFDEF AW_PROFILE}Inc(RenderProfile.PenTicks,TStopwatch.GetTimeStamp-Stamp);{$ENDIF}
  end;
end;

initialization
  InitializeQuillSections;
end.
