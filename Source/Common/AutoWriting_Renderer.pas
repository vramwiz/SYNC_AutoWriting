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
    FEngine: TWritingFontEngine;
    FKey: string;
    FRevision: Integer;
    FGlyphs: TArray<TPlacedGlyph>;
    FSegments: TArray<TPenSegment>;
    FBounds: TRectF;
    FTotalDistance: Double;
    procedure BuildLayout(const S: TWritingSettings);
  public
    constructor Create;
    destructor Destroy; override;
    procedure Prepare(const S: TWritingSettings);
    // 解析済みの総距離÷速度（秒）。出力拡大率やオブジェクト長は使用しない。
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

implementation

uses System.SysUtils, System.Math, System.Generics.Collections, AviUtl2FilterTypes, AutoWriting_Learning;

constructor TWritingRenderer.Create;
begin inherited; FEngine:=TWritingFontEngine.Create; FRevision:=-1 end;

destructor TWritingRenderer.Destroy;
begin FEngine.Free; inherited end;

procedure TWritingRenderer.Prepare(const S: TWritingSettings);
var Key: string;
begin
  Key:=S.Text+'|'+SettingsJSON(S);
  if (Key=FKey) and (FRevision=LearningRevision) then Exit;
  FKey:=''; FRevision:=-1;
  FGlyphs:=nil; FSegments:=nil; FEngine.Configure(S); BuildLayout(S);
  FKey:=Key; FRevision:=LearningRevision;
end;

procedure TWritingRenderer.BuildLayout(const S: TWritingSettings);
var Characters: TArray<string>; C: string; G: TWritingGlyph; PG: TPlacedGlyph;
  Placed: TList<TPlacedGlyph>; Segments: TList<TPenSegment>; Seg: TPenSegment;
  CursorX,CursorY,Size,Ratio,Cell,LocalStart,StrokeStart,PosX,PosY: Double;
  Last,A,B: TPointF; HavePen,HaveBounds: Boolean; I,J: Integer;
  procedure AddSegment(const P1,P2: TPointF; Down: Boolean; MinLength: Double=0);
  begin
    Seg.A:=P1; Seg.B:=P2; Seg.Length:=Max(MinLength,Distance(P1,P2));
    Seg.StartDistance:=FTotalDistance; Seg.Down:=Down;
    if Seg.Length>0 then begin Segments.Add(Seg); FTotalDistance:=FTotalDistance+Seg.Length end;
  end;
begin
  Placed:=TList<TPlacedGlyph>.Create; Segments:=TList<TPenSegment>.Create;
  try
    FTotalDistance:=0; FBounds:=TRectF.Empty; CursorX:=0; CursorY:=0;
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
      LocalStart:=FTotalDistance;
      for I:=0 to High(G.Strokes) do
      begin
        if Length(G.Strokes[I].Points)=0 then Continue;
        A:=G.Strokes[I].Points[0]; A:=PointF(PG.X+A.X*PG.Scale,PG.Y+A.Y*PG.Scale);
        if HavePen then AddSegment(Last,A,False);
        if I=0 then LocalStart:=FTotalDistance;
        StrokeStart:=FTotalDistance;
        for J:=1 to High(G.Strokes[I].Points) do
        begin
          B:=G.Strokes[I].Points[J]; B:=PointF(PG.X+B.X*PG.Scale,PG.Y+B.Y*PG.Scale);
          AddSegment(A,B,True); A:=B;
        end;
        // 点も一定距離を使う。ゼロ長画で時間が消えないようにする。
        if FTotalDistance-StrokeStart<G.Strokes[I].Length*PG.Scale then
          AddSegment(A,A,True,G.Strokes[I].Length*PG.Scale-(FTotalDistance-StrokeStart));
        Last:=A; HavePen:=True;
      end;
      PG.StartDistance:=LocalStart; PG.EndDistance:=FTotalDistance; Placed.Add(PG);
      if S.Vertical then CursorY:=CursorY+Size+Size*S.LetterGap
      else CursorX:=CursorX+Cell+Size*S.LetterGap;
    end;
    FGlyphs:=Placed.ToArray; FSegments:=Segments.ToArray;
  finally Segments.Free; Placed.Free end;
end;

function TWritingRenderer.Duration(const S: TWritingSettings): Double;
begin Prepare(S); Result:=FTotalDistance/SafeNumber(S.Speed,240,1,10000) end;

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

procedure DrawPen(var Output: TWritingPixels; W,H: Integer; const Tip: TPointF;
  const S: TWritingSettings; GlobalScale,Opacity,Lift: Double);
var X,Y,X0,Y0,X1,Y1,SX,SY,Hits: Integer;
  Angle,CS,SN,Scale,Len,Radius,U,V,PX,PY,Width: Double; Color,SampleColor: Cardinal;
  RSum,GSum,BSum: Integer;
begin
  Angle:=(S.PenAngle-90)*Pi/180; CS:=Cos(Angle); SN:=Sin(Angle);
  Scale:=Max(0.02,S.PenSize*GlobalScale); Len:=78; Radius:=Len*Scale+3;
  X0:=Max(0,Floor(Tip.X-Radius)); X1:=Min(W-1,Ceil(Tip.X+Radius));
  Y0:=Max(0,Floor(Tip.Y-Radius)); Y1:=Min(H-1,Ceil(Tip.Y+Radius));
  for Y:=Y0 to Y1 do for X:=X0 to X1 do
  begin
    Hits:=0; RSum:=0; GSum:=0; BSum:=0;
    for SY:=0 to 1 do for SX:=0 to 1 do
    begin
      PX:=X+0.25+SX*0.5-Tip.X; PY:=Y+0.25+SY*0.5-Tip.Y;
      U:=(PX*CS+PY*SN)/Scale; V:=(-PX*SN+PY*CS)/Scale;
      if (U<0) or (U>Len) then Continue;
      Width:=4; SampleColor:=$2C3554;
      case S.Pen of
        pkPencil: begin
          Width:=Min(4,U*0.4); SampleColor:=$E9B949;
          if U<11 then SampleColor:=$CFAB7A; if U<3 then SampleColor:=$303034;
          if U>70 then SampleColor:=$CB777D;
        end;
        pkBallpoint: begin
          Width:=Min(3.5,0.6+U*0.3); SampleColor:=$34679C;
          if U<8 then SampleColor:=$A6AFBC; if U<2 then SampleColor:=$202028;
          if (U>22) and (V< -1.5) then SampleColor:=$82A8CE;
        end;
        pkFountain: begin
          if U<14 then begin Width:=Min(U*0.55,(18-U)*0.55); SampleColor:=$D5AE57 end
          else begin Width:=4.5; SampleColor:=$333047 end;
          if U<2 then SampleColor:=$202028;
          if (U>18) and (U<21) then SampleColor:=$CDB477;
        end;
        pkBrush: begin
          if U<22 then begin Width:=Sin(U/28*Pi)*5.5; SampleColor:=$252026 end
          else begin Width:=2.8; SampleColor:=$96683D end;
        end;
      end;
      if Abs(V)>Width then Continue;
      Inc(Hits); Inc(RSum,(SampleColor shr 16) and 255);
      Inc(GSum,(SampleColor shr 8) and 255); Inc(BSum,SampleColor and 255);
    end;
    if Hits=0 then Continue;
    Color:=(Cardinal(RSum div Hits) shl 16) or (Cardinal(GSum div Hits) shl 8) or Cardinal(BSum div Hits);
    Blend(Output[Y*W+X],Color,Round(Hits*255*Opacity*(1-Lift*0.15)/4));
  end;
end;

procedure TWritingRenderer.Render(const Input: TWritingPixels; Width,Height: Integer;
  Time: Double; const S: TWritingSettings; var Output: TWritingPixels);
var GlobalScale,OffsetX,OffsetY,Opacity,D,LocalD,Scale,PX,PY,FX,FY,Alpha,WX,WY: Double;
  PG: TPlacedGlyph; G: TWritingGlyph; X,Y,X0,Y0,X1,Y1,IX,IY,SX,SY,MX,MY,Index: Integer;
  Complete: Boolean; Pen: TPointF; Lift: Double;
begin
  if (Width<=0) or (Height<=0) or (Width>8192) or (Height>8192) or
    (Int64(Width)*Height>AW_MAX_PIXELS) then raise EArgumentException.Create('Invalid output dimensions');
  Prepare(S); SetLength(Output,Width*Height);
  if Length(Input)=Length(Output) then Move(Input[0],Output[0],Length(Output)*SizeOf(TPIXEL_RGBA))
  else FillChar(Output[0],Length(Output)*SizeOf(TPIXEL_RGBA),0);
  GlobalScale:=SafeNumber(S.Scale,100,0,1000)/100;
  Opacity:=1-SafeNumber(S.Transparency,0,0,100)/100;
  if (GlobalScale<=0) or (Opacity<=0) then Exit;
  D:=SafeNumber(Time,0,0,1E12)*SafeNumber(S.Speed,240,1,10000);
  OffsetX:=Width/2+S.X-(FBounds.Left+FBounds.Right)/2*GlobalScale;
  OffsetY:=Height/2+S.Y-(FBounds.Top+FBounds.Bottom)/2*GlobalScale;
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
  if S.ShowPen and PenAt(D,Pen,Lift) then
  begin
    Pen:=PointF(OffsetX+Pen.X*GlobalScale,OffsetY+(Pen.Y-S.LiftHeight*Lift)*GlobalScale);
    DrawPen(Output,Width,Height,Pen,S,GlobalScale,Opacity,Lift);
  end;
end;

end.
