unit AutoWriting_ReferenceTests;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// 本番AUF2と同じ推定器を使う比較検査。Contextは呼出中だけ借用する。
// 元の学習は読取専用。保存試験はGUIDで作った専用IDだけを使用し、最後に削除する。
interface

uses AutoWriting_PenTests;

procedure TestStrokeReferences(const Context: TPenTestContext; const OutputDirectory: string);

implementation

uses System.SysUtils, System.Types, System.Math, System.Classes, System.IOUtils, System.JSON, System.NetEncoding,
  AutoWriting_Types, AutoWriting_Fonts, AutoWriting_Inference, AutoWriting_ReferenceData,
  AutoWriting_ReferenceFit, AutoWriting_Learning, AutoWriting_Renderer, AutoWriting_Preview, AutoWriting_ReferenceOrder,
  AutoWriting_FontCatalog;

procedure TestFontListAndWheel(const Context: TPenTestContext);
var Names: TStringList; I,R,Position: Integer; E: TWritingFontEngine; S: TWritingSettings; ID: string;
begin
  Names:=TStringList.Create; E:=TWritingFontEngine.Create;
  try
    ListWritingFonts(Names); Context.Check(Names.Count>10,'Outline font combo has installed fonts');
    Context.Check((Names.IndexOf('游明朝')>=0) and (Names.IndexOf('ＭＳ ゴシック')>=0),'Font combo includes the checked Japanese families');
    for I:=0 to Names.Count-1 do
    begin
      Context.Check((Names[I]<>'') and (Names[I][1]<>'@'),'Font combo excludes vertical aliases');
      if I>0 then Context.Check(not SameText(Names[I],Names[I-1]),'Font combo excludes duplicate families');
    end;
    S:=DefaultWritingSettings; E.Configure(S); ID:=E.FontID; S.FontName:='ＭＳ ゴシック'; E.Configure(S);
    Context.Check(E.FontID<>ID,'Font combo selection changes the actual font identity');
    R:=0; Position:=SettingsWheelPosition(0,900,600,-120,48,R); Context.Check(Position=48,'Overflow wheel scrolls down');
    Position:=SettingsWheelPosition(Position,900,600,120,48,R); Context.Check(Position=0,'Overflow wheel scrolls up');
    Context.Check(SettingsWheelPosition(0,500,600,-120,48,R)=0,'Fitting settings do not scroll');
    Context.Check(SettingsWheelPosition(290,900,600,-120,48,R)=300,'Wheel clamps at content end');
    Context.Check(SettingsWheelPosition(0,900,600,-30,48,R)=12,'High precision wheel is preserved');
  finally E.Free; Names.Free end;
end;

procedure TestReferenceOrderFallback(const Context: TPenTestContext);
var G: TWritingGlyph; Targets: TArray<TArray<TPointF>>; Improvement: Double; Reason: string;
  Original: TArray<TPointF>;
begin
  G:=TWritingGlyph.Create;
  try
    SetLength(G.Strokes,3); SetLength(Targets,3);
    Targets[0]:=TArray<TPointF>.Create(PointF(10,10),PointF(10,90));
    Targets[1]:=TArray<TPointF>.Create(PointF(20,40),PointF(70,40));
    Targets[2]:=TArray<TPointF>.Create(PointF(80,10),PointF(80,90));
    G.Strokes[0].ID:=13; G.Strokes[0].Points:=TArray<TPointF>.Create(PointF(80,90),PointF(80,10));
    G.Strokes[1].ID:=11; G.Strokes[1].Points:=TArray<TPointF>.Create(PointF(10,90),PointF(10,10));
    G.Strokes[1].PinnedVertices:=TArray<Integer>.Create(0); Original:=G.Strokes[1].Points;
    G.Strokes[2].ID:=12; G.Strokes[2].Points:=Copy(Targets[1]);
    Context.Check(ApplyReferenceOrder(G,Targets,Improvement,Reason),'Reference-order fallback applied');
    Context.Check((G.Strokes[0].ID=11) and (G.Strokes[1].ID=12) and (G.Strokes[2].ID=13),'Reference-order fallback fixes known stroke order');
    Context.Check((G.Strokes[0].Points[0].Y=10) and (G.Strokes[2].Points[0].Y=10),'Reference-order fallback fixes downward direction');
    Context.Check((Original[0].Y=90) and (G.Strokes[0].PinnedVertices[0]=1),'Reference-order preserves original storage and editing vertices');
    Context.Check(not ApplyReferenceOrder(G,Targets,Improvement,Reason),'Correctly ordered paths are stable');
  finally G.Free end;
end;

procedure TestPreviewContrast(const Context: TPenTestContext);
var S: TWritingSettings; Colour: Cardinal; BG: Byte; Source,Original,Display: TWritingPixels;
  Row: TBytes; X,Y,W,H,I: Integer;
begin
  Context.Check(PreviewBackground($000000)=255,'Black ink uses white preview background');
  Context.Check(PreviewBackground($FFFFFF)=0,'White ink uses black preview background');
  Context.Check(PreviewBackground($FF0000)=0,'Red ink contrast');
  Context.Check(PreviewBackground($0000FF)=255,'Blue ink contrast');
  SetLength(Source,3); SetLength(Row,12);
  Source[0].A:=0; Source[1].A:=128; Source[2].A:=255;
  CompositePreviewRow(Source,0,3,255,@Row[0]);
  Context.Check((Row[0]=255) and (Row[4]=127) and (Row[8]=0) and (Row[11]=255),'Preview alpha over white');
  Source[1].R:=255; Source[1].G:=255; Source[1].B:=255;
  CompositePreviewRow(Source,0,3,0,@Row[0]); Context.Check(Row[4]=128,'Preview alpha over black');
  S:=DefaultWritingSettings; S.Text:='こんにちは ABC 012'; S.FontName:='游明朝'; S.FontSize:=60; S.ShowPen:=False;
  W:=800; H:=240; Context.SizeFrame(W,H);
  for Colour in TArray<Cardinal>.Create($000000,$FFFFFF) do
  begin
    S.InkColor:=Colour; BG:=PreviewBackground(Colour); Context.Configure(S); Source:=Context.Render(10000); Original:=Copy(Source);
    SetLength(Display,W*H); SetLength(Row,W*4);
    for Y:=0 to H-1 do
    begin
      CompositePreviewRow(Source,Y*W,W,BG,@Row[0]);
      for X:=0 to W-1 do
      begin I:=Y*W+X; Display[I].B:=Row[X*4]; Display[I].G:=Row[X*4+1]; Display[I].R:=Row[X*4+2]; Display[I].A:=255 end;
    end;
    Context.Check(CompareMem(@Source[0],@Original[0],Length(Source)*4),'Preview preserves video RGBA');
    Context.Check((Display[0].R=BG) and (Display[0].G=BG) and (Display[0].B=BG),'Preview solid opposing background');
    Context.SavePNG(Display,W,H,'preview_contrast_'+IntToHex(Colour,6)+'.png');
  end;
  Writeln('PASS black/white preview backgrounds, coloured ink contrast and alpha composition');
end;

function CloneShape(G: TWritingGlyph): TWritingGlyph;
begin
  Result:=TWritingGlyph.Create; Result.Character:=G.Character; Result.FontID:=G.FontID; Result.FontFace:=G.FontFace;
  Result.Width:=G.Width; Result.Height:=G.Height; Result.OriginX:=G.OriginX; Result.OriginY:=G.OriginY;
  Result.Advance:=G.Advance; Result.Mask:=Copy(G.Mask); Result.Missing:=G.Missing;
end;

function SamePaths(const A,B: TArray<TStroke>): Boolean;
var I,J: Integer;
begin
  Result:=False; if Length(A)<>Length(B) then Exit;
  for I:=0 to High(A) do
  begin
    if Length(A[I].Points)<>Length(B[I].Points) then Exit;
    for J:=0 to High(A[I].Points) do if Distance(A[I].Points[J],B[I].Points[J])>0.0001 then Exit;
  end;
  Result:=True;
end;

function PathLength(const Points: TArray<TPointF>): Double;
var I: Integer;
begin Result:=0; for I:=1 to High(Points) do Result:=Result+Distance(Points[I-1],Points[I]) end;

function PathsJSON(G: TWritingGlyph): TJSONArray;
var S: TStroke; P: TPointF; A,B: TJSONArray;
begin
  Result:=TJSONArray.Create;
  for S in G.Strokes do
  begin
    A:=TJSONArray.Create; Result.AddElement(A);
    for P in S.Points do begin B:=TJSONArray.Create; B.Add(P.X); B.Add(P.Y); A.AddElement(B) end;
  end;
end;

procedure CheckPrintedForm(const Context: TPenTestContext; Glyph: TWritingGlyph;
  const Info: TReferenceFitInfo; ExpectedCount: Integer);
var
  Bars, I: Integer;
  Lower, Slant, Stroke: TArray<TPointF>;
  StartPoint, EndPoint: TPointF;
  Description: string;
begin
  Description := 'U+' + IntToHex(Ord(Glyph.Character[1]), 4) + ': ';
  Context.Check((Info.VariantIndex > 0) and (Info.Mode = 'paths') and
    (Length(Glyph.Strokes) = ExpectedCount), Description + 'printed form stroke count');
  if Glyph.Character = 'a' then
  begin
    Stroke := Glyph.Strokes[0].Points;
    StartPoint := Stroke[0];
    EndPoint := Stroke[High(Stroke)];
    Context.Check((EndPoint.X > StartPoint.X) and (EndPoint.Y > StartPoint.Y + Glyph.Height * 0.4),
      Description + 'top arch ends at the foot of the right stem');
    Lower := Glyph.Strokes[1].Points;
    Context.Check((Lower[0].X > Glyph.Width * 0.5) and (Lower[High(Lower)].X > Glyph.Width * 0.5) and
      (Lower[Length(Lower) div 2].X < Glyph.Width * 0.5), Description + 'bowl goes around the left and rejoins the stem');
    Exit;
  end;
  if Glyph.Character = 'g' then
  begin
    Stroke := Glyph.Strokes[0].Points;
    Context.Check(Distance(Stroke[0], Stroke[High(Stroke)]) < 4, Description + 'upper loop closes first');
    Context.Check(Glyph.Strokes[1].Points[Length(Glyph.Strokes[1].Points) div 2].Y > Glyph.Height * 0.65,
      Description + 'lower loop follows the upper loop');
    Exit;
  end;
  Bars := 1;
  if (Glyph.Character = 'き') or (Glyph.Character = 'ぎ') then Bars := 2;
  for I := 0 to Bars - 1 do
  begin
    Stroke := Glyph.Strokes[I].Points;
    Context.Check(Stroke[High(Stroke)].X - Stroke[0].X > Glyph.Width * 0.5,
      Description + 'upper bars run from left to right');
  end;
  Slant := Glyph.Strokes[Bars].Points;
  Lower := Glyph.Strokes[Bars + 1].Points;
  EndPoint := Slant[High(Slant)];
  Context.Check((EndPoint.X > Slant[0].X) and (EndPoint.Y > Slant[0].Y + Glyph.Height * 0.4),
    Description + 'slant descends to the right after the bars');
  Context.Check(Distance(EndPoint, Lower[0]) < Glyph.Width * 0.12,
    Description + 'lower curve starts near the junction as a separate stroke');
  Context.Check((Lower[Length(Lower) div 2].X < Lower[0].X - Glyph.Width * 0.3) and
    (Lower[High(Lower)].X > Lower[Length(Lower) div 2].X + Glyph.Width * 0.3) and
    (Lower[High(Lower)].Y > Lower[0].Y + Glyph.Height * 0.15),
    Description + 'lower curve turns left and then finishes to the right at the bottom');
  if ExpectedCount > Bars + 2 then
  begin
    StartPoint := Glyph.Strokes[Bars + 2].Points[0];
    EndPoint := Glyph.Strokes[Bars + 3].Points[0];
    Context.Check((StartPoint.X < EndPoint.X) and (StartPoint.Y < Glyph.Height * 0.3) and
      (EndPoint.Y < Glyph.Height * 0.3), Description + 'dakuten follow the body in left to right order');
  end;
end;

procedure CheckEBodyFold(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  Body: TStroke;
  I, Pixel: Integer;
  P, Finish: TPointF;
  Travel, AtFold: Double;
begin
  Context.Check(Length(Glyph.Strokes) = 2, 'E: upper mark and a single continuous body');
  PrepareGlyphTiming(Glyph);
  Body := Glyph.Strokes[1];
  Finish := Body.Points[High(Body.Points)];
  Context.Check((Body.Points[0].X < Glyph.Width * 0.4) and
    (Finish.X > Glyph.Width * 0.75) and (Finish.Y > Glyph.Height * 0.75),
    'E: the body starts at the left bar and finishes at the lower right');
  Travel := 0;
  for I := 1 to High(Body.Points) - 1 do
  begin
    P := Body.Points[I];
    Travel := Travel + Distance(Body.Points[I - 1], P);
    if (P.X > Glyph.Width * 0.22) or (P.Y < Glyph.Height * 0.75) or
      (Distance(Body.Points[I - 1], Body.Points[I + 1]) > 0.001) then Continue;
    AtFold := Body.StartDistance + Travel;
    Pixel := Round(P.Y) * Glyph.Width + Round(P.X);
    Context.Check((Glyph.Mask[Pixel] > 0) and (Glyph.Reveal[Pixel] <= AtFold + 1),
      'E: the lower-left ink appears on reaching the fold');
    Pixel := Round(Finish.Y) * Glyph.Width + Round(Finish.X);
    Context.Check(Glyph.Reveal[Pixel] > AtFold, 'E: the lower-right finish follows the fold');
    Exit;
  end;
  Context.Check(False, 'E: the body must reach the lower-left tip and double back');
end;

procedure CheckTePath(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  Body: TStroke;
  StartPoint, Finish, P: TPointF;
  I, Fold, Pixel, StrokeCount: Integer;
  Travel, FoldDistance, Step: Double;
begin
  StrokeCount := 1;
  if Glyph.Character = 'で' then StrokeCount := 3;
  Context.Check(Length(Glyph.Strokes) = StrokeCount, 'Te: one body stroke plus any dakuten');
  PrepareGlyphTiming(Glyph);
  Body := Glyph.Strokes[0];
  StartPoint := Body.Points[0];
  Finish := Body.Points[High(Body.Points)];
  Context.Check((StartPoint.X < Glyph.Width * 0.25) and (StartPoint.Y < Glyph.Height * 0.35) and
    (Finish.X > Glyph.Width * 0.65) and (Finish.Y > Glyph.Height * 0.8),
    'Te: write from the upper left to the lower-right tail');

  Travel := 0;
  Fold := -1;
  FoldDistance := 0;
  for I := 1 to High(Body.Points) do
  begin
    P := Body.Points[I];
    Step := Distance(Body.Points[I - 1], P);
    Context.Check((Step > 0) and (Step < 1.5), 'Te: the body path is continuous');
    Travel := Travel + Step;
    if Fold >= 0 then Continue;
    Context.Check(P.Y < Glyph.Height * 0.35, 'Te: the upper line precedes the lower curve');
    if (I < High(Body.Points)) and (P.X > Glyph.Width * 0.75) and
      (Distance(Body.Points[I - 1], Body.Points[I + 1]) < 0.001) then
    begin
      Fold := I;
      FoldDistance := Travel;
    end;
  end;
  Context.Check(Fold >= 0, 'Te: the pen reaches the upper-right tip before turning back');
  P := Body.Points[Fold];
  Pixel := Round(P.Y) * Glyph.Width + Round(P.X);
  Context.Check((Glyph.Mask[Pixel] > 0) and (Glyph.Reveal[Pixel] <= FoldDistance + 1),
    'Te: paint the upper-right tip at the turn');
  Pixel := Round(Finish.Y) * Glyph.Width + Round(Finish.X);
  Context.Check(Glyph.Reveal[Pixel] > FoldDistance, 'Te: paint the lower curve after the turn');
  if StrokeCount = 3 then
    Context.Check(Glyph.Strokes[1].Points[0].X < Glyph.Strokes[2].Points[0].X,
      'De: the two separate dakuten follow the body from left to right');
end;

procedure CheckLatinUppercasePaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  First, Second, Third, Bar: TArray<TPointF>;
  A, B, P: TPointF;
  Expected, I, Branch: Integer;
  Step, LeftDepth, RightDepth, Rightmost: Double;
  PassedMiddle, PassedRightShoulder: Boolean;
begin
  case Glyph.Character[1] of
    'E': Expected:=4;
    'A', 'F', 'H', 'K', 'N', 'R', 'Y': Expected:=3;
    'L', 'V', 'W': Expected:=1;
  else
    Expected:=2;
  end;
  Context.Check(Length(Glyph.Strokes)=Expected, 'Uppercase '+Glyph.Character+': stroke count');
  for var Stroke in Glyph.Strokes do
  begin
    Context.Check(Length(Stroke.Points)>8, 'Uppercase: no separate dot for a serif or tip');
    for I:=1 to High(Stroke.Points) do
    begin
      Step:=Distance(Stroke.Points[I-1],Stroke.Points[I]);
      Context.Check((Step>0) and (Step<1.5), 'Uppercase: every stroke follows the font centerline');
    end;
  end;
  First:=Glyph.Strokes[0].Points;
  A:=First[0]; B:=First[High(First)];
  if Expected>=2 then Second:=Glyph.Strokes[1].Points;
  if Expected>=3 then Third:=Glyph.Strokes[2].Points;
  if Pos(Glyph.Character,'EFHKLMNPR')>0 then
    Context.Check((A.X<Glyph.Width*0.3) and (A.Y<Glyph.Height*0.2) and
      ((B.Y>Glyph.Height*0.8) or (Glyph.Character='L')), 'Uppercase: start with the left downward stem');
  case Glyph.Character[1] of
    'A':
      begin
        Context.Check((A.Y<Glyph.Height*0.25) and (B.X<A.X) and (B.Y>Glyph.Height*0.8),
          'A: first diagonal goes from the apex down left');
        B:=Second[High(Second)];
        Context.Check((Second[0].Y<Glyph.Height*0.25) and (B.X>Second[0].X) and (B.Y>Glyph.Height*0.8),
          'A: second diagonal goes down right');
        Context.Check(Third[High(Third)].X-Third[0].X>Glyph.Width*0.28, 'A: crossbar goes left to right last');
      end;
    'E', 'F':
      for Branch:=1 to Expected-1 do
      begin
        Bar:=Glyph.Strokes[Branch].Points;
        Context.Check((Bar[High(Bar)].X-Bar[0].X>Glyph.Width*0.4) and
          (Bar[0].Y>Glyph.Height*(Branch-1)*0.35) and
          (Bar[0].Y<Glyph.Height*(Branch-1)*0.35+Glyph.Height*0.28),
          'E/F: write horizontal bars left to right in top-to-bottom order');
      end;
    'H':
      begin
        B:=Second[High(Second)];
        Context.Check((Second[0].X>Glyph.Width*0.65) and (Second[0].Y<Glyph.Height*0.2) and
          (B.Y>Glyph.Height*0.8), 'H: write the right stem second');
        Context.Check(Third[High(Third)].X-Third[0].X>Glyph.Width*0.5, 'H: draw the crossbar last');
      end;
    'K':
      begin
        B:=Second[High(Second)];
        Context.Check((B.X<Second[0].X) and (B.Y>Second[0].Y), 'K: second diagonal runs down left');
        B:=Third[High(Third)];
        Context.Check((B.X>Third[0].X) and (B.Y>Third[0].Y), 'K: third diagonal runs down right');
      end;
    'L':
      begin
        LeftDepth:=0;
        for P in First do if P.X<Glyph.Width*0.35 then LeftDepth:=Max(LeftDepth,P.Y);
        Context.Check((LeftDepth>Glyph.Height*0.85) and (B.X>Glyph.Width*0.75),
          'L: reach the corner and write across the bottom in one stroke');
      end;
    'M':
      begin
        B:=Second[High(Second)];
        PassedMiddle:=False; PassedRightShoulder:=False;
        for P in Second do
        begin
          if (P.X>Glyph.Width*0.4) and (P.X<Glyph.Width*0.62) and (P.Y>Glyph.Height*0.52) then PassedMiddle:=True;
          if PassedMiddle and (P.X>Glyph.Width*0.68) and (P.Y<Glyph.Height*0.27) then PassedRightShoulder:=True;
        end;
        Context.Check((Second[0].X<Glyph.Width*0.25) and (Second[0].Y<Glyph.Height*0.2) and
          PassedRightShoulder and (B.X>Glyph.Width*0.65) and (B.Y>Glyph.Height*0.8),
          'M: continue through the inner bend, upper right and right stem');
      end;
    'N':
      begin
        B:=Second[High(Second)];
        Context.Check((Second[0].X<Glyph.Width*0.27) and (Second[0].Y<Glyph.Height*0.25) and
          (B.X>Glyph.Width*0.7) and (B.Y>Glyph.Height*0.8), 'N: middle stroke is the downward diagonal');
        B:=Third[High(Third)];
        Context.Check((Third[0].X>Glyph.Width*0.65) and (Third[0].Y<Glyph.Height*0.2) and
          (B.Y>Glyph.Height*0.8), 'N: write the right stem from top to bottom last');
      end;
    'P', 'R':
      begin
        B:=Second[High(Second)]; Rightmost:=0;
        for P in Second do Rightmost:=Max(Rightmost,P.X);
        Context.Check((Second[0].X<Glyph.Width*0.3) and (Second[0].Y<Glyph.Height*0.2) and
          (Rightmost>Glyph.Width*0.65) and (B.X<Glyph.Width*0.33) and (B.Y>Glyph.Height*0.33),
          'P/R: upper bowl starts at the stem and curves back to it');
        if Glyph.Character='R' then
        begin
          B:=Third[High(Third)];
          Context.Check((B.X>Third[0].X) and (B.Y>Third[0].Y), 'R: last leg descends to the right');
        end;
      end;
    'T':
      begin
        Context.Check((A.X<Glyph.Width*0.2) and (B.X>Glyph.Width*0.8) and
          (Max(A.Y,B.Y)<Glyph.Height*0.28), 'T: top bar runs left to right first');
        B:=Second[High(Second)];
        Context.Check((Second[0].X>Glyph.Width*0.35) and (Second[0].X<Glyph.Width*0.65) and
          (Second[0].Y<Glyph.Height*0.2) and (B.Y>Glyph.Height*0.8), 'T: finish with the middle stem');
      end;
    'V', 'W':
      begin
        LeftDepth:=0; RightDepth:=0;
        for P in First do
          if P.X<Glyph.Width*0.5 then LeftDepth:=Max(LeftDepth,P.Y) else RightDepth:=Max(RightDepth,P.Y);
        Context.Check((A.X<Glyph.Width*0.22) and (B.X>Glyph.Width*0.8) and (Max(A.Y,B.Y)<Glyph.Height*0.2) and
          (Max(LeftDepth,RightDepth)>Glyph.Height*0.8), 'V/W: write the bend from left to right without lifting');
        if Glyph.Character='W' then Context.Check(Min(LeftDepth,RightDepth)>Glyph.Height*0.8,
          'W: visit both lower turns within the only stroke');
      end;
    'X', 'Y':
      begin
        Context.Check((B.X>A.X) and (B.Y>A.Y), 'X/Y: first diagonal runs down right');
        B:=Second[High(Second)];
        Context.Check((B.X<Second[0].X) and (B.Y>Second[0].Y), 'X/Y: second diagonal runs down left');
        if Glyph.Character='Y' then
          Context.Check((Third[0].Y>Glyph.Height*0.35) and (Third[High(Third)].Y>Glyph.Height*0.8),
            'Y: the lower stem follows both diagonals');
      end;
  end;
end;

procedure CheckLatinLowercasePaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  First, Second, Third: TStroke;
  I, X, Y, Expected, DotBottom, LeftValley, RightValley, DotPixels: Integer;
  P, StartPoint, Finish: TPointF;
  Step, Direction: Double;
begin
  case Glyph.Character[1] of
    'l', 'v', 'w': Expected := 1;
    'k', 'm': Expected := 3;
  else
    Expected := 2;
  end;
  Context.Check(Length(Glyph.Strokes) = Expected, 'Lowercase ' + Glyph.Character + ': expected stroke count');
  for var Stroke in Glyph.Strokes do
  begin
    if (Glyph.Character = 'i') and (Stroke.ID = Glyph.Strokes[1].ID) then Continue;
    Context.Check(Length(Stroke.Points) > 8, 'Latin: no orphan stroke for a serif');
    for I := 1 to High(Stroke.Points) do
    begin
      Step := Distance(Stroke.Points[I - 1], Stroke.Points[I]);
      Context.Check((Step > 0) and (Step < 1.5), 'Latin: one continuous font path per stroke');
    end;
  end;

  First := Glyph.Strokes[0];
  StartPoint := First.Points[0];
  Finish := First.Points[High(First.Points)];
  if Expected >= 2 then Second := Glyph.Strokes[1];
  if Expected >= 3 then Third := Glyph.Strokes[2];
  case Glyph.Character[1] of
    'd', 'q':
      begin
        Context.Check((StartPoint.X > Glyph.Width * 0.65) and (Finish.X > Glyph.Width * 0.65) and
          (Finish.Y > StartPoint.Y), 'Latin: start the bowl at the upper right and finish at the lower attachment');
        for P in First.Points do if P.X < Glyph.Width * 0.2 then Break;
        Context.Check(P.X < Glyph.Width * 0.2, 'Latin: the first stroke covers the left edge of the bowl');
        P := Second.Points[High(Second.Points)];
        Context.Check((Second.Points[0].X > Glyph.Width * 0.65) and (P.Y > Glyph.Height * 0.84),
          'Latin: follow the bowl with the right stem');
      end;
    'k':
      begin
        Context.Check((StartPoint.Y < Glyph.Height * 0.15) and (Finish.Y > Glyph.Height * 0.84),
          'k: write the stem first');
        P := Second.Points[High(Second.Points)];
        Context.Check((P.X < Second.Points[0].X) and (P.Y > Second.Points[0].Y), 'k: descend left into the stem');
        P := Third.Points[High(Third.Points)];
        Context.Check((P.X > Third.Points[0].X) and (P.Y > Third.Points[0].Y), 'k: descend right from the junction');
      end;
    'm', 'r':
      begin
        Context.Check((StartPoint.X < Glyph.Width * 0.45) and (StartPoint.Y < Glyph.Height * 0.20) and
          (Finish.Y > Glyph.Height * 0.8), 'Latin: write the short left stem before the arch');
        P := Second.Points[High(Second.Points)];
        Context.Check(P.X > Second.Points[0].X, 'Latin: the arch sweeps to the right');
        if Glyph.Character = 'm' then
          Context.Check((Third.Points[0].X > Second.Points[0].X) and (Third.Points[High(Third.Points)].X > P.X),
            'm: the third stem belongs to the right arch');
      end;
    'v', 'w':
      begin
        Context.Check((StartPoint.X < Glyph.Width * 0.3) and (Finish.X > Glyph.Width * 0.7) and
          (StartPoint.Y < Glyph.Height * 0.25) and (Finish.Y < Glyph.Height * 0.25), 'Latin: zigzag runs left to right');
        LeftValley:=0; RightValley:=0;
        for P in First.Points do
          if P.X < Glyph.Width * 0.5 then LeftValley:=Max(LeftValley,Round(P.Y))
          else RightValley:=Max(RightValley,Round(P.Y));
        Context.Check(Max(LeftValley,RightValley) > Glyph.Height * 0.77, 'Latin: visit the bottom bend');
        if Glyph.Character='w' then Context.Check(Min(LeftValley,RightValley) > Glyph.Height * 0.77,
          'w: visit both bottom bends in the same stroke');
      end;
    'x':
      begin
        P:=Second.Points[High(Second.Points)];
        Context.Check((Finish.X > StartPoint.X) and (Finish.Y > StartPoint.Y) and
          (P.X < Second.Points[0].X) and (P.Y > Second.Points[0].Y), 'x: downward right diagonal followed by downward left');
      end;
    'i':
      begin
        Context.Check((Finish.Y > StartPoint.Y + Glyph.Height * 0.45) and
          (Second.Points[0].Y < StartPoint.Y - Glyph.Height * 0.14), 'i: write the stem, then reach the separate dot');
        PrepareGlyphTiming(Glyph);
        DotBottom := Round(Second.Points[0].Y);
        while DotBottom+1<Round(StartPoint.Y) do
        begin
          Y:=DotBottom+1;
          X:=0;
          while (X<Glyph.Width) and (Glyph.Mask[Y*Glyph.Width+X]=0) do Inc(X);
          if X=Glyph.Width then Break;
          Inc(DotBottom);
        end;
        DotPixels:=0;
        for I:=0 to (DotBottom+1)*Glyph.Width-1 do
          if Glyph.Mask[I]<>0 then
          begin
            Inc(DotPixels);
            Direction:=Glyph.Reveal[I]-Glyph.Strokes[1].StartDistance;
            Context.Check((Direction>=-0.001) and (Direction<=Glyph.Strokes[1].Length),
              'i: dot pixels appear during contact of the second stroke');
          end;
        Context.Check(DotPixels>0, 'i: verify ink across the actual dot');
      end;
  end;
end;

procedure CheckKatakanaBatchPaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  First, Second, Third, Fourth: TArray<TPointF>;
  P, Finish: TPointF;
  I, Expected: Integer;
  Step, Rightmost: Double;
  ReachedTip: Boolean;
begin
  case Glyph.Character[1] of
    'タ', 'ゥ': Expected := 3;
    'ネ': Expected := 4;
  else
    Expected := 2;
  end;
  Context.Check(Length(Glyph.Strokes) = Expected, 'Katakana: correct number of strokes');
  for var Stroke in Glyph.Strokes do
  begin
    Context.Check(Length(Stroke.Points) > 8, 'Katakana: no isolated fragment');
    for I := 1 to High(Stroke.Points) do
    begin
      Step := Distance(Stroke.Points[I - 1], Stroke.Points[I]);
      Context.Check((Step > 0) and (Step < 1.5), 'Katakana: pen stays on the centerline during each stroke');
    end;
  end;

  First := Glyph.Strokes[0].Points;
  Second := Glyph.Strokes[1].Points;
  if Expected >= 3 then Third := Glyph.Strokes[2].Points;
  case Glyph.Character[1] of
    'タ':
      begin
        Finish := First[High(First)];
        Context.Check((First[0].Y < Glyph.Height * 0.13) and (Finish.X < Glyph.Width * 0.15) and
          (Finish.Y > Glyph.Height * 0.44), 'Ta: descend to the left in the first stroke');
        Finish := Second[High(Second)];
        Rightmost := 0;
        for P in Second do Rightmost := Max(Rightmost, P.X);
        Context.Check((Second[0].Y < Glyph.Height * 0.30) and (Rightmost > Glyph.Width * 0.82) and
          (Finish.Y > Glyph.Height * 0.86) and (Finish.X < Glyph.Width * 0.33),
          'Ta: the second stroke goes right, then down to the lower-left tip');
        Finish := Third[High(Third)];
        Context.Check((Third[0].Y > Glyph.Height * 0.36) and (Finish.X - Third[0].X > Glyph.Width * 0.24) and
          (Finish.Y > Third[0].Y), 'Ta: write the inner diagonal from left to right last');
      end;
    'ネ':
      begin
        Context.Check((First[0].Y < Glyph.Height * 0.12) and (First[High(First)].Y < Glyph.Height * 0.24),
          'Ne: write the short upper stroke first');
        for P in First do Context.Check(P.Y < Glyph.Height * 0.26, 'Ne: first stroke ends above the center');
        Finish := Second[High(Second)];
        Rightmost := 0;
        for P in Second do Rightmost := Max(Rightmost, P.X);
        Context.Check((Second[0].X < Glyph.Width * 0.2) and (Rightmost > Glyph.Width * 0.65) and
          (Finish.X < Glyph.Width * 0.13) and (Finish.Y > Glyph.Height * 0.65),
          'Ne: write the upper horizontal and left sweep as one stroke');
        Finish := Third[High(Third)];
        Context.Check((Third[0].Y > Glyph.Height * 0.43) and (Finish.Y > Glyph.Height * 0.86) and
          (Abs(Finish.X - Third[0].X) < Glyph.Width * 0.12), 'Ne: the third stroke descends vertically');
        Fourth := Glyph.Strokes[3].Points;
        Context.Check((Fourth[0].X > Third[0].X) and (Fourth[High(Fourth)].X > Glyph.Width * 0.86) and
          (Fourth[High(Fourth)].Y > Fourth[0].Y), 'Ne: write the right diagonal last');
      end;
    'ム':
      begin
        Finish := First[High(First)];
        Context.Check((First[0].Y < Glyph.Height * 0.13) and (Finish.X > Glyph.Width * 0.75),
          'Mu: the first stroke runs from the top through the lower-left bend to the right');
        ReachedTip := False;
        for I := 1 to High(First) - 1 do
          if (First[I].X < Glyph.Width * 0.07) and (First[I].Y > Glyph.Height * 0.8) and
            (Distance(First[I - 1], First[I + 1]) < 0.001) then ReachedTip := True;
        Context.Check(ReachedTip, 'Mu: turn at the actual left tip during the first stroke');
        Finish := Second[High(Second)];
        Context.Check((Second[0].X > Glyph.Width * 0.65) and (Finish.X > Second[0].X) and
          (Finish.Y > Second[0].Y), 'Mu: last stroke is the right diagonal');
      end;
    'ゥ':
      begin
        Finish := First[High(First)];
        Context.Check((First[0].Y < Glyph.Height * 0.12) and (Finish.Y < Glyph.Height * 0.32) and
          (First[0].X > Glyph.Width * 0.3), 'Small U: write the short top stroke first');
        for P in Second do Context.Check(P.X < Glyph.Width * 0.2, 'Small U: second stroke stays at the left');
        Context.Check(Second[High(Second)].Y > Glyph.Height * 0.43, 'Small U: write the left vertical down');
        Rightmost := 0;
        for P in Third do Rightmost := Max(Rightmost, P.X);
        Finish := Third[High(Third)];
        Context.Check((Third[0].X < Glyph.Width * 0.2) and (Rightmost > Glyph.Width * 0.82) and
          (Finish.X < Glyph.Width * 0.46) and (Finish.Y > Glyph.Height * 0.85),
          'Small U: last stroke goes right and curves back down to the left');
      end;
    'ヒ':
      begin
        Finish := First[High(First)];
        Context.Check((First[0].X > Glyph.Width * 0.7) and (Finish.X < Glyph.Width * 0.26),
          'Hi: first stroke travels from right to left');
        Finish := Second[High(Second)];
        Context.Check((Second[0].X < Glyph.Width * 0.2) and (Second[0].Y < Glyph.Height * 0.17) and
          (Finish.X > Glyph.Width * 0.8) and (Finish.Y > Glyph.Height * 0.85),
          'Hi: second stroke starts at the top left and bends to the right');
      end;
  end;
end;

procedure CheckKatakanaAPaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  Top, Sweep: TArray<TPointF>;
  P, Finish: TPointF;
  Rightmost, Step: Double;
begin
  Context.Check(Length(Glyph.Strokes) = 2, 'Katakana A: two strokes without a final dot');
  for var Stroke in Glyph.Strokes do
  begin
    Context.Check(Length(Stroke.Points) > 30, 'Katakana A: each stroke must be a full path');
    for var I := 1 to High(Stroke.Points) do
    begin
      Step := Distance(Stroke.Points[I - 1], Stroke.Points[I]);
      Context.Check((Step > 0) and (Step < 1.5), 'Katakana A: continuous pen movement');
    end;
  end;

  Top := Glyph.Strokes[0].Points;
  Finish := Top[High(Top)];
  Rightmost := 0;
  for P in Top do
  begin
    Context.Check(P.Y < Glyph.Height * 0.57, 'Katakana A: first stroke stays in the upper part');
    Rightmost := Max(Rightmost, P.X);
  end;
  Context.Check((Top[0].X < Glyph.Width * 0.15) and (Top[0].Y < Glyph.Height * 0.2) and
    (Rightmost > Glyph.Width * 0.82) and (Rightmost - Finish.X > Glyph.Width * 0.20),
    'Katakana A: write left to right and turn down toward the center');

  Sweep := Glyph.Strokes[1].Points;
  Finish := Sweep[High(Sweep)];
  Context.Check((Sweep[0].X > Glyph.Width * 0.32) and (Sweep[0].X < Glyph.Width * 0.56) and
    (Sweep[0].Y < Glyph.Height * 0.42) and (Finish.X < Glyph.Width * 0.30) and
    (Finish.Y > Glyph.Height * 0.83), 'Katakana A: finish the second stroke at the lower-left tip');
end;

procedure CheckWaWoNPaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  Lead, Body, Tail: TArray<TPointF>;
  StartPoint, Finish, P: TPointF;
  I, Expected: Integer;
  MinTurnY, Rightmost, Step: Double;
  Turned: Boolean;
begin
  case Glyph.Character[1] of
    'わ': Expected := 2;
    'を': Expected := 3;
  else
    Expected := 1;
  end;
  Context.Check(Length(Glyph.Strokes) = Expected, 'Wa/Wo/N: canonical stroke count');
  for var Stroke in Glyph.Strokes do
  begin
    Context.Check(Length(Stroke.Points) > 30, 'Wa/Wo/N: no isolated fragment');
    for I := 1 to High(Stroke.Points) do
    begin
      Step := Distance(Stroke.Points[I - 1], Stroke.Points[I]);
      Context.Check((Step > 0) and (Step < 1.5), 'Wa/Wo/N: continuous path before each pen lift');
    end;
  end;

  Lead := Glyph.Strokes[0].Points;
  Body := Lead;
  if Expected > 1 then Body := Glyph.Strokes[1].Points;
  StartPoint := Body[0];
  Finish := Body[High(Body)];
  MinTurnY := Glyph.Height * 0.66;
  case Glyph.Character[1] of
    'わ':
      begin
        Context.Check((Lead[0].Y < Glyph.Height * 0.12) and (Lead[High(Lead)].Y > Glyph.Height * 0.90),
          'Wa: write the left vertical from top to bottom');
        for P in Lead do
          Context.Check(P.X < Glyph.Width * 0.42, 'Wa: the right curve comes after the left vertical');
        Context.Check((StartPoint.X < Glyph.Width * 0.15) and (StartPoint.Y < Glyph.Height * 0.43) and
          (Finish.X > Glyph.Width * 0.45) and (Finish.Y > Glyph.Height * 0.85), 'Wa: write into the right curve');
      end;
    'を':
      begin
        for P in Lead do
          Context.Check(P.Y < Glyph.Height * 0.3, 'Wo: write the top horizontal first');
        Context.Check((Lead[0].X < Glyph.Width * 0.15) and (Lead[High(Lead)].X > Glyph.Width * 0.55) and
          (StartPoint.Y < Glyph.Height * 0.15) and (Finish.Y > Glyph.Height * 0.69),
          'Wo: top horizontal goes right, followed by the descending second stroke');
        Tail := Glyph.Strokes[2].Points;
        Context.Check((Tail[0].X > Glyph.Width * 0.75) and (Tail[0].Y < Glyph.Height * 0.49) and
          (Tail[High(Tail)].X > Glyph.Width * 0.69) and (Tail[High(Tail)].Y > Glyph.Height * 0.92),
          'Wo: the last stroke starts at the right and the curve ends at the bottom right');
        MinTurnY := Glyph.Height * 0.48;
      end;
    'ん':
      begin
        Context.Check((StartPoint.Y < Glyph.Height * 0.15) and (Finish.X > Glyph.Width * 0.85) and
          (Finish.Y < Glyph.Height * 0.72), 'N: descend from the top and sweep up to the right in one stroke');
        MinTurnY := Glyph.Height * 0.80;
      end;
  end;

  Turned := False;
  Rightmost := 0;
  for I := 1 to High(Body) - 1 do
  begin
    P := Body[I];
    if (P.X < Glyph.Width * 0.14) and (P.Y > MinTurnY) and
      (Distance(Body[I - 1], Body[I + 1]) < 0.001) then Turned := True;
    if Turned then Rightmost := Max(Rightmost, P.X);
  end;
  Context.Check(Turned and (Rightmost >= Finish.X - 1), 'Wa/Wo/N: visit the left tip before turning back to the right');
  if Glyph.Character = 'わ' then
    Context.Check(Rightmost > Glyph.Width * 0.85, 'Wa: round the right side before finishing');
end;

procedure CheckRiRePaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  LeftPath, Body: TArray<TPointF>;
  StartPoint, Finish, P: TPointF;
  LeftBottom, BodyTop, Rightmost, Step: Double;
  I: Integer;
  Turned: Boolean;
begin
  Context.Check(Length(Glyph.Strokes) = 2, 'Ri/Re: exactly two strokes');
  for var Stroke in Glyph.Strokes do
  begin
    Context.Check(Length(Stroke.Points) > 30, 'Ri/Re: no isolated dot');
    for I := 1 to High(Stroke.Points) do
    begin
      Step := Distance(Stroke.Points[I - 1], Stroke.Points[I]);
      Context.Check((Step > 0) and (Step < 1.5), 'Ri/Re: pen follows a continuous font path');
    end;
  end;
  LeftPath := Glyph.Strokes[0].Points;
  LeftBottom := 0;
  for P in LeftPath do
  begin
    Context.Check(P.X < Glyph.Width * 0.5, 'Ri/Re: write the left stroke first');
    LeftBottom := Max(LeftBottom, P.Y);
  end;
  Context.Check(LeftPath[0].Y < Glyph.Height * 0.2, 'Ri/Re: start the first stroke at its top');

  Body := Glyph.Strokes[1].Points;
  StartPoint := Body[0];
  Finish := Body[High(Body)];
  BodyTop := Glyph.Height;
  Rightmost := 0;
  for P in Body do
  begin
    BodyTop := Min(BodyTop, P.Y);
    Rightmost := Max(Rightmost, P.X);
  end;
  Context.Check(Rightmost > Glyph.Width * 0.8, 'Ri/Re: second stroke reaches the right side');
  if Glyph.Character = 'り' then
  begin
    Context.Check((LeftBottom > Glyph.Height * 0.45) and (LeftBottom < Glyph.Height * 0.75) and
      (BodyTop < Glyph.Height * 0.23) and (Finish.Y > Glyph.Height * 0.85) and
      (Finish.X < Rightmost - Glyph.Width * 0.2), 'Ri: the long right stroke sweeps down and left');
    Exit;
  end;

  Context.Check((LeftPath[High(LeftPath)].Y > Glyph.Height * 0.85) and
    (StartPoint.X < Glyph.Width * 0.22) and (StartPoint.Y < Glyph.Height * 0.5) and
    (Finish.X > Glyph.Width * 0.85) and (Finish.Y > Glyph.Height * 0.6),
    'Re: finish the left vertical, then write from the left branch through to the right');
  Turned := False;
  for I := 1 to High(Body) - 1 do
  begin
    P := Body[I];
    if (P.X < Glyph.Width * 0.2) and (P.Y > Glyph.Height * 0.65) and
      (Distance(Body[I - 1], Body[I + 1]) < 0.001) then
      Turned := True;
    if P.X > Glyph.Width * 0.65 then
    begin
      Context.Check(Turned, 'Re: turn back at the lower left before entering the right arc');
      Break;
    end;
  end;
end;

procedure CheckWiYuWePaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  Path: TArray<TPointF>;
  P, StartPoint, Finish: TPointF;
  I, Expected: Integer;
  Step, Leftmost, Rightmost, Bottom: Double;
  PassedRightArc, PassedLowerLeft: Boolean;
begin
  Expected := 1;
  if Glyph.Character = 'ゆ' then Expected := 2;
  Context.Check(Length(Glyph.Strokes) = Expected, 'Wi/Yu/We: canonical stroke count');
  for I := 0 to Expected - 1 do
  begin
    Path := Glyph.Strokes[I].Points;
    Context.Check(Length(Path) > 10, 'Wi/Yu/We: no isolated dot');
    for var J := 1 to High(Path) do
    begin
      Step := Distance(Path[J - 1], Path[J]);
      Context.Check((Step > 0) and (Step < 1.5), 'Wi/Yu/We: pen follows a continuous font path');
    end;
  end;
  Path := Glyph.Strokes[0].Points;
  StartPoint := Path[0];
  Finish := Path[High(Path)];
  Leftmost := Glyph.Width;
  Rightmost := 0;
  Bottom := 0;
  for P in Path do
  begin
    Leftmost := Min(Leftmost, P.X);
    Rightmost := Max(Rightmost, P.X);
    Bottom := Max(Bottom, P.Y);
  end;
  if Glyph.Character = 'ゆ' then
  begin
    Context.Check((StartPoint.X < Glyph.Width * 0.2) and (Bottom > Glyph.Height * 0.6) and
      (Rightmost > Glyph.Width * 0.85), 'Yu: first stroke starts at the left and rounds the right');
    Path := Glyph.Strokes[1].Points;
    Finish := Path[High(Path)];
    Context.Check((Path[0].X > Glyph.Width * 0.48) and (Path[0].Y < Glyph.Height * 0.2) and
      (Finish.Y > Bottom + Glyph.Height * 0.08) and (Finish.X < Path[0].X),
      'Yu: second stroke descends through the first and sweeps left below it');
    Exit;
  end;
  Context.Check((StartPoint.Y < Glyph.Height * 0.2) and (StartPoint.X < Glyph.Width * 0.45) and
    (Finish.Y > Glyph.Height * 0.75) and (Finish.X > Glyph.Width * 0.7) and
    (Leftmost < Glyph.Width * 0.24) and (Rightmost > Glyph.Width * 0.8),
    'Wi/We: write from the upper-left start through to the lower right');
  if Glyph.Character = 'ゑ' then
  begin
    PassedRightArc := False;
    PassedLowerLeft := False;
    for P in Path do
    begin
      if (P.X > Glyph.Width * 0.6) and (P.Y > Glyph.Height * 0.3) and (P.Y < Glyph.Height * 0.62) then
        PassedRightArc := True;
      if PassedRightArc and (P.X < Glyph.Width * 0.24) and (P.Y > Glyph.Height * 0.72) then
        PassedLowerLeft := True;
    end;
    Context.Check(PassedLowerLeft, 'We: traverse the middle arc before the lower-left turn and final wave');
  end;
end;

procedure CheckMuMoPaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  Path: TArray<TPointF>;
  Starts, Ends: array[0..2] of TPointF;
  P: TPointF;
  I: Integer;
  Bottom, Step: Double;
  LeftLoop: Boolean;
begin
  Context.Check(Length(Glyph.Strokes) = 3, 'Mu/Mo: three complete strokes');
  for I := 0 to 2 do
  begin
    Path := Glyph.Strokes[I].Points;
    Context.Check(Length(Path) > 10, 'Mu/Mo: preserve a distinct path for each stroke');
    for var J := 1 to High(Path) do
    begin
      Step := Distance(Path[J - 1], Path[J]);
      Context.Check((Step > 0) and (Step < 1.5), 'Mu/Mo: use a continuous font centerline');
    end;
    Starts[I] := Path[0];
    Ends[I] := Path[High(Path)];
  end;
  if Glyph.Character = 'む' then
  begin
    Context.Check((Ends[0].X - Starts[0].X > Glyph.Width * 0.3) and
      (Starts[0].Y < Glyph.Height * 0.35) and (Ends[0].Y < Glyph.Height * 0.35),
      'Mu: the upper bar runs left to right first');
    LeftLoop := False;
    Bottom := 0;
    for P in Glyph.Strokes[1].Points do
    begin
      if (P.X < Glyph.Width * 0.2) and (P.Y > Glyph.Height * 0.35) and (P.Y < Glyph.Height * 0.82) then
        LeftLoop := True;
      Bottom := Max(Bottom, P.Y);
    end;
    Context.Check((Starts[1].X < Glyph.Width * 0.48) and (Starts[1].Y < Glyph.Height * 0.16) and
      LeftLoop and (Bottom > Glyph.Height * 0.85) and (Ends[1].X > Glyph.Width * 0.67),
      'Mu: the second stroke descends, goes through the left loop and sweeps right');
    Context.Check((Starts[2].X > Glyph.Width * 0.66) and (Ends[2].Y > Starts[2].Y),
      'Mu: the upper-right stroke comes last');
    Exit;
  end;
  Bottom := 0;
  for P in Glyph.Strokes[0].Points do Bottom := Max(Bottom, P.Y);
  Context.Check((Starts[0].X > Glyph.Width * 0.22) and (Starts[0].Y < Glyph.Height * 0.18) and
    (Bottom > Glyph.Height * 0.85) and (Ends[0].Y < Bottom - Glyph.Height * 0.2) and
    (Ends[0].X > Glyph.Width * 0.6), 'Mo: the first stroke descends and curves up on the right');
  Context.Check((Ends[1].X - Starts[1].X > Glyph.Width * 0.3) and
    (Ends[2].X - Starts[2].X > Glyph.Width * 0.2) and (Ends[1].Y < Ends[2].Y),
    'Mo: write the upper crossbar, then the lower crossbar, from left to right');
end;

procedure CheckFuHoPaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  Path: TArray<TPointF>;
  StartPoints, EndPoints: array[0..3] of TPointF;
  P: TPointF;
  I: Integer;
  Leftmost, Rightmost, Bottom: Double;
begin
  Context.Check(Length(Glyph.Strokes) = 4, 'Fu/Ho: four complete strokes');
  for I := 0 to 3 do
  begin
    Path := Glyph.Strokes[I].Points;
    Context.Check((Length(Path) >= 14) and (PathLength(Path) >= 14),
      'Fu/Ho: no short leftover dot in place of a stroke');
    for var J := 1 to High(Path) do
      Context.Check(Distance(Path[J - 1], Path[J]) < 1.5, 'Fu/Ho: each stroke is continuous');
    StartPoints[I] := Path[0];
    EndPoints[I] := Path[High(Path)];
  end;
  if Glyph.Character = 'ふ' then
  begin
    Context.Check((StartPoints[0].Y < Glyph.Height * 0.25) and
      (EndPoints[0].Y < Glyph.Height * 0.3), 'Fu: the upper mark is first');
    Bottom := 0;
    for P in Glyph.Strokes[1].Points do Bottom := Max(Bottom, P.Y);
    Context.Check((StartPoints[1].X > Glyph.Width * 0.25) and
      (StartPoints[1].X < Glyph.Width * 0.67) and (Bottom > Glyph.Height * 0.85),
      'Fu: the second stroke follows the central curve to the bottom');
    Leftmost := Glyph.Width;
    for P in Glyph.Strokes[2].Points do Leftmost := Min(Leftmost, P.X);
    Rightmost := 0;
    for P in Glyph.Strokes[3].Points do Rightmost := Max(Rightmost, P.X);
    Context.Check((Leftmost < Glyph.Width * 0.2) and
      (StartPoints[3].X > Glyph.Width * 0.45) and (Rightmost > Glyph.Width * 0.85),
      'Fu: the complete left and right marks come third and fourth');
    Exit;
  end;
  Bottom := 0;
  for P in Glyph.Strokes[0].Points do Bottom := Max(Bottom, P.Y);
  Context.Check((StartPoints[0].X < Glyph.Width * 0.25) and (Bottom > Glyph.Height * 0.75),
    'Ho: the left stroke comes first');
  for I := 1 to 2 do
    Context.Check(EndPoints[I].X - StartPoints[I].X > Glyph.Width * 0.35,
      'Ho: each crossbar is a single stroke from left to right');
  Context.Check((StartPoints[1].Y < StartPoints[2].Y) and (EndPoints[1].Y < EndPoints[2].Y),
    'Ho: upper crossbar precedes the lower crossbar');
  Bottom := 0;
  for P in Glyph.Strokes[3].Points do Bottom := Max(Bottom, P.Y);
  Context.Check((StartPoints[3].Y < StartPoints[2].Y) and (Bottom > Glyph.Height * 0.85) and
    (EndPoints[3].X > Glyph.Width * 0.8), 'Ho: the fourth stroke descends, loops and finishes at the right');
end;

procedure CheckNaNePaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  Path, Body: TArray<TPointF>;
  P, StartPoint, Finish: TPointF;
  I, Expected: Integer;
  AtLeftTip, UpperArc, LowerCurve, Loop: Boolean;
begin
  Expected := 2;
  if Glyph.Character = 'な' then Expected := 4;
  Context.Check(Length(Glyph.Strokes) = Expected, 'Na/Ne: canonical stroke count');
  for I := 0 to Expected - 1 do
  begin
    Path := Glyph.Strokes[I].Points;
    Context.Check(Length(Path) > 2, 'Na/Ne: each stroke has a path');
    for var J := 1 to High(Path) do
      Context.Check(Distance(Path[J - 1], Path[J]) < 1.5, 'Na/Ne: continuous font centerline');
  end;
  Path := Glyph.Strokes[0].Points;
  StartPoint := Path[0];
  Finish := Path[High(Path)];
  if Glyph.Character = 'な' then
  begin
    Context.Check((Finish.X > StartPoint.X + Glyph.Width * 0.3) and
      (Abs(Finish.Y - StartPoint.Y) < Glyph.Height * 0.16), 'Na: horizontal stroke first, from left to right');
    Path := Glyph.Strokes[1].Points;
    Finish := Path[High(Path)];
    Context.Check((Path[0].Y < StartPoint.Y) and (Finish.X < Path[0].X) and
      (Finish.Y > Glyph.Height * 0.6), 'Na: second stroke descends to the left');
    Path := Glyph.Strokes[2].Points;
    Context.Check((Path[0].X > Glyph.Width * 0.54) and (Path[0].Y < Glyph.Height * 0.42),
      'Na: the upper-right mark precedes the loop');
    Body := Glyph.Strokes[3].Points;
    Finish := Body[High(Body)];
    Loop := False;
    for P in Body do
      Loop := Loop or ((P.X < Body[0].X - Glyph.Width * 0.2) and (P.Y > Glyph.Height * 0.82));
    Context.Check(Loop and (Finish.X > Glyph.Width * 0.8) and (Finish.Y > Glyph.Height * 0.75),
      'Na: the fourth stroke goes through the loop and finishes on the right');
    Exit;
  end;

  Context.Check((StartPoint.X < Glyph.Width * 0.4) and (Finish.Y > Glyph.Height * 0.8) and
    (Finish.Y > StartPoint.Y), 'Ne: the left vertical stroke comes first');
  Body := Glyph.Strokes[1].Points;
  Finish := Body[High(Body)];
  Context.Check((Body[0].X < Glyph.Width * 0.2) and (Body[0].Y < Glyph.Height * 0.45),
    'Ne: the continuous body starts on the left');
  AtLeftTip := False;
  UpperArc := False;
  LowerCurve := False;
  Loop := False;
  for I := 1 to High(Body) - 1 do
  begin
    P := Body[I];
    if (P.X < Glyph.Width * 0.2) and (P.Y > Glyph.Height * 0.65) and
      (Distance(Body[I - 1], Body[I + 1]) < 0.001) then AtLeftTip := True;
    if AtLeftTip and (P.X > Glyph.Width * 0.65) and (P.Y < Glyph.Height * 0.45) then UpperArc := True;
    if UpperArc and (P.X > Glyph.Width * 0.65) and (P.Y > Glyph.Height * 0.8) then LowerCurve := True;
    if LowerCurve and (P.X < Glyph.Width * 0.65) and (P.Y > Glyph.Height * 0.68) then Loop := True;
  end;
  Context.Check(Loop and (Finish.X > Glyph.Width * 0.85) and (Finish.Y > Glyph.Height * 0.7),
    'Ne: the second stroke turns at the lower left, crosses above and completes the lower-right loop');
end;

procedure CheckKaKePaths(const Context: TPenTestContext; Glyph: TWritingGlyph);
var
  First, Second, Third, StartPoint, Finish, PointOnStroke: TPointF;
  Points: TArray<TPointF>;
  Expected, I, J: Integer;
  Rightmost, Lowest, Step: Double;
begin
  Expected := 3;
  if (Glyph.Character = 'が') or (Glyph.Character = 'げ') then Expected := 5;
  Context.Check(Length(Glyph.Strokes) = Expected, 'Ka/Ke: three main strokes plus any dakuten');
  for I := 0 to 2 do
  begin
    Points := Glyph.Strokes[I].Points;
    Context.Check(Length(Points) > 3, 'Ka/Ke: no isolated point in a main stroke');
    for J := 1 to High(Points) do
    begin
      Step := Distance(Points[J - 1], Points[J]);
      Context.Check((Step > 0) and (Step < 1.5), 'Ka/Ke: each main stroke is continuous');
    end;
  end;
  First := Glyph.Strokes[0].Points[0];
  Second := Glyph.Strokes[1].Points[0];
  Third := Glyph.Strokes[2].Points[0];
  if Pos(Glyph.Character, 'かがゕ') > 0 then
  begin
    Points := Glyph.Strokes[0].Points;
    Rightmost := First.X;
    for PointOnStroke in Points do Rightmost := Max(Rightmost, PointOnStroke.X);
    Finish := Points[High(Points)];
    Context.Check((First.X < Glyph.Width * 0.2) and (Rightmost > Glyph.Width * 0.45) and
      (Finish.Y > Glyph.Height * 0.65), 'Ka: the first stroke starts at the left and turns down');
    Points := Glyph.Strokes[1].Points;
    Finish := Points[High(Points)];
    Context.Check((Second.Y < First.Y) and (Finish.X < Second.X - Glyph.Width * 0.12) and
      (Finish.Y > Glyph.Height * 0.75), 'Ka: second stroke descends to the left');
    Points := Glyph.Strokes[2].Points;
    Finish := Points[High(Points)];
    Context.Check((Third.X > Glyph.Width * 0.6) and (Finish.Y > Third.Y + Glyph.Height * 0.16),
      'Ka: the separate right-hand stroke comes last');
  end
  else
  begin
    Lowest := First.Y;
    for PointOnStroke in Glyph.Strokes[0].Points do Lowest := Max(Lowest, PointOnStroke.Y);
    Context.Check((First.X < Glyph.Width * 0.25) and (Lowest > Glyph.Height * 0.55),
      'Ke: the left stroke extends down before the crossbar');
    Points := Glyph.Strokes[1].Points;
    Finish := Points[High(Points)];
    Context.Check((Finish.X > Second.X + Glyph.Width * 0.3) and
      (Abs(Finish.Y - Second.Y) < Glyph.Height * 0.2), 'Ke: the second stroke crosses continuously to the right');
    Points := Glyph.Strokes[2].Points;
    Finish := Points[High(Points)];
    Context.Check((Third.Y < Second.Y) and (Finish.Y > Glyph.Height * 0.75),
      'Ke: the final stroke runs from above the crossbar to the bottom');
  end;
  if Expected = 5 then
  begin
    StartPoint := Glyph.Strokes[3].Points[0];
    Finish := Glyph.Strokes[4].Points[0];
    Context.Check((StartPoint.X < Finish.X) and (StartPoint.Y < Glyph.Height * 0.3) and
      (Finish.Y < Glyph.Height * 0.3), 'Ka/Ke: the separate dakuten are written after the body');
  end;
end;

procedure TestStrokeReferences(const Context: TPenTestContext; const OutputDirectory: string);
var Engine: TWritingFontEngine; S: TWritingSettings; G,B,C,Loaded: TWritingGlyph;
  Reference: TStrokeReference; Variant: TReferenceVariant; Info: TReferenceFitInfo; Rows: TJSONArray; Row,Summary: TJSONObject;
  Mask: TBytes; Before: TArray<TStroke>; Code: Cardinal; FontName,Text,ID,Folder,Warning: string;
  I,J,K,F,Total,Accepted,Hira,Kata,Latin,CountBefore,CountAfter,Learned,OrderOnly,Trimmed: Integer;
  Used,Found: Boolean; P,Q: TPointF; ErrorBefore: Double; Pixels,Expected: TWritingPixels;
  procedure Check(OK: Boolean; const MessageText: string);
  begin Context.Check(OK,'Reference: '+MessageText) end;
begin
  TestFontListAndWheel(Context); TestReferenceOrderFallback(Context); TestPreviewContrast(Context); Check(StrokeReferenceCount=238,'238 character coverage');
  for I:=0 to StrokeReferenceCount-1 do
  begin
    Code:=StrokeReferenceCodepoint(I); if I>0 then Check(Code>StrokeReferenceCodepoint(I-1),'sorted unique index');
    Check(FindStrokeReference(Code,Reference),'index lookup');
    Check(Length(Reference.Variants)>=1,'canonical variant');
    for Variant in Reference.Variants do
      for J:=0 to High(Variant) do
      begin
        Check(Length(Variant[J].Points)>=2,'path endpoints');
        for P in Variant[J].Points do Check((P.X>=0) and (P.X<=1) and (P.Y>=0) and (P.Y<=1),'normal coordinates');
      end;
  end;
  Check(not FindStrokeReference(Ord('漢'),Reference),'kanji is future work');
  Check(not FindStrokeReference($1F600,Reference),'unknown supplementary codepoint');
  Engine:=TWritingFontEngine.Create; Rows:=TJSONArray.Create;
  Total:=0; Accepted:=0; Hira:=0; Kata:=0; Latin:=0; CountBefore:=0; CountAfter:=0; Learned:=0; OrderOnly:=0; Trimmed:=0;
  try
    for F:=0 to 4 do
    begin
      case F of 0: FontName:='ＭＳ ゴシック'; 1: FontName:='游明朝'; 2: FontName:='メイリオ'; 3: FontName:='Arial'; else FontName:='Times New Roman' end;
      S:=DefaultWritingSettings; S.FontName:=FontName; Engine.Configure(S);
      for I:=0 to StrokeReferenceCount-1 do
      begin
        Code:=StrokeReferenceCodepoint(I); Text:=Char(Code); G:=Engine.Glyph(Text);
        Check(Engine.Glyph(Text)=G,'same-character cache identity');
        if G.Missing then Continue;
        if G.Learned then begin Inc(Learned); Check(not G.ReferenceUsed,'learning has priority') end;
        B:=CloneShape(G); C:=CloneShape(G);
        try
          InferGlyphStrokes(B,False); InferGlyphStrokes(C,False); Before:=C.Strokes; Mask:=Copy(C.Mask);
          Used:=TryApplyStrokeReference(C,Info); Inc(Total);
          if (F<=2) and ((Text='あ') or (Text='お')) then
          begin
            Check(Used and (Info.Mode='paths') and (Length(C.Strokes)=3),'Reported kana must reconstruct three actual font strokes');
            Check(C.Strokes[0].Points[High(C.Strokes[0].Points)].X>C.Strokes[0].Points[0].X,'Kana first bar writes left to right');
            Check(C.Strokes[1].Points[High(C.Strokes[1].Points)].Y>C.Strokes[1].Points[0].Y,'Kana second stroke starts above its ending');
            if Text='お' then
              for P in C.Strokes[2].Points do Check((P.X>C.Width*0.55) and (P.Y<C.Height*0.6),'O isolated upper-right stroke is last');
          end;
          if (F=1) and (Text='い') then
          begin
            Check(Used and (Info.Mode='trim') and (Length(C.Strokes)=2), 'Yu Mincho i has no third pen trip');
            P:=B.Strokes[2].Points[High(B.Strokes[2].Points)];
            J:=Round(P.Y)*C.Width+Round(P.X);
            PrepareGlyphTiming(C);
            Check((C.Mask[J]>0) and (C.Reveal[J]<=C.Strokes[0].Length),
              'the leftover ink appears by the end of the first stroke');
            Check(C.TotalDistance<B.Strokes[2].StartDistance, 'the return after stroke two is removed');
          end;
          if (F<=2) and ((Text='え') or (Text='ぇ')) then
          begin
            Check(Used and (Info.Mode='paths'), 'the E body is reconstructed from the font centerline');
            CheckEBodyFold(Context,C);
          end;
          if (F<=2) and (Pos(Text,'かがゕけげゖ')>0) then
          begin
            Check(Used and (Info.Mode='paths'), 'Ka/Ke: the whole strokes are reconstructed');
            CheckKaKePaths(Context,C);
          end;
          if (F<=2) and ((Text='て') or (Text='で')) then
          begin
            Check(Used and (Info.Mode='paths'), 'Te: reconstruct a single continuous body');
            CheckTePath(Context,C);
          end;
          if (F<=2) and ((Text='な') or (Text='ね')) then
          begin
            Check(Used and (Info.Mode='paths'), 'Na/Ne: reconstruct complete font strokes');
            CheckNaNePaths(Context,C);
          end;
          if (F<=2) and ((Text='ふ') or (Text='ほ')) then CheckFuHoPaths(Context,C);
          if (F<=2) and ((Text='む') or (Text='も')) then
          begin
            Check(Used and (Info.Mode='paths'), 'Mu/Mo: reconstruct complete font strokes');
            CheckMuMoPaths(Context,C);
          end;
          if (F<=2) and (Pos(Text,'ゐゆゑ')>0) then
          begin
            Check(Used and (Info.Mode='paths'), 'Wi/Yu/We: reconstruct complete font strokes');
            CheckWiYuWePaths(Context,C);
          end;
          if (F<=2) and (Pos(Text,'りれ')>0) then
          begin
            if Text='れ' then Check(Used and (Info.Mode='paths'), 'Re: reconstruct complete font strokes');
            CheckRiRePaths(Context,C);
          end;
          if (F<=2) and (Pos(Text,'わをん')>0) then
          begin
            Check(Used and (Info.Mode='paths'), 'Wa/Wo/N: reconstruct complete strokes with planned turn');
            CheckWaWoNPaths(Context,C);
          end;
          if (F<=2) and (Text='ア') then CheckKatakanaAPaths(Context,C);
          if (F<=2) and (Pos(Text,'タネムゥヒ')>0) then
          begin
            Check(Used, 'Reported katakana uses a reference path or direction');
            CheckKatakanaBatchPaths(Context,C);
          end;
          if (F<=2) and (Text='き') then CheckPrintedForm(Context,C,Info,4);
          if (F<=2) and (Text='さ') then CheckPrintedForm(Context,C,Info,3);
          if (F<=1) and (Text='ぎ') then CheckPrintedForm(Context,C,Info,6);
          if (F<=2) and (Text='ざ') then CheckPrintedForm(Context,C,Info,5);
          if Text='a' then CheckPrintedForm(Context,C,Info,2);
          if ((F<=1) or (F=4)) and (Text='g') then CheckPrintedForm(Context,C,Info,2);
          if Pos(Text,'bdghiklmnpqruvwx')>0 then CheckLatinLowercasePaths(Context,C);
          if Pos(Text,'AEFHKLMNPRTVWXY')>0 then CheckLatinUppercasePaths(Context,C);
          if (F<=2) and (Pos(Text,'シツソン')>0) then
          begin
            if (Text='シ') or (Text='ツ') then Check(Length(C.Strokes)=3,'Katakana: three strokes')
            else Check(Length(C.Strokes)=2,'Katakana: two strokes');
            J:=High(C.Strokes);
            P:=C.Strokes[J].Points[0]; Q:=C.Strokes[J].Points[High(C.Strokes[J].Points)];
            if (Text='シ') or (Text='ン') then
              Check((Q.X>P.X) and (Q.Y<P.Y),'Shi/N: final sweep rises toward the right')
            else Check((Q.X<P.X) and (Q.Y>P.Y),'Tsu/So: final sweep descends toward the left');
          end;
          Check(Length(C.Mask)=Length(Mask),'mask length unchanged');
          Check(CompareMem(@Mask[0],@C.Mask[0],Length(Mask)),'font shape unchanged');
          FindStrokeReference(Code,Reference);
          if Length(B.Strokes)=Length(Reference.Variants[0]) then Inc(CountBefore);
          if Length(C.Strokes)=Length(Reference.Variants[0]) then Inc(CountAfter);
          if Used then
          begin
            Inc(Accepted); if Code<$80 then Inc(Latin) else if Code<$30A0 then Inc(Hira) else Inc(Kata);
            if Info.Mode='trim' then
            begin
              Inc(Trimmed);
              Check(Length(B.Strokes)=Length(C.Strokes)+1, 'only the trailing branch was removed');
              Check(SamePaths(C.Strokes,Copy(B.Strokes,0,Length(C.Strokes))), 'main stroke order and points are unchanged');
            end
            else Check(Info.Coverage>=0.92,'skeleton coverage');
            if Info.Mode='order' then
            begin
              Inc(OrderOnly); Check(Info.OrderImprovement>=8,'confident order/direction correction');
              Check(Length(C.Strokes)=Length(B.Strokes),'order-only preserves stroke geometry/count');
              for J:=0 to High(B.Strokes) do
              begin
                Found:=False;
                for K:=0 to High(C.Strokes) do if C.Strokes[K].ID=B.Strokes[J].ID then
                begin
                  Found:=Length(C.Strokes[K].Points)=Length(B.Strokes[J].Points);
                  if Found then Check(Abs(PathLength(C.Strokes[K].Points)-PathLength(B.Strokes[J].Points))<0.001,'order-only preserves path length');
                  Break;
                end;
                Check(Found,'order-only preserves every source stroke');
              end;
            end
            else if Info.Mode='paths' then Check(Info.AfterError+0.75<Info.BeforeError,'clear ordered improvement');
            for J:=0 to High(C.Strokes) do for P in C.Strokes[J].Points do
            begin
              Found:=False;
              for K:=0 to High(B.Strokes) do for Q in B.Strokes[K].Points do
                if Distance(P,Q)<0.001 then begin Found:=True; Break end;
              if not Found and (Info.RecoveredComponents>0) then
                Found:=(P.X>=0) and (P.Y>=0) and (P.X<C.Width) and (P.Y<C.Height) and (C.Mask[Round(P.Y)*C.Width+Round(P.X)]>=64);
              Check(Found,'every fitted vertex belongs to the actual font skeleton or recovered ink dot');
            end;
          end
          else Check(SamePaths(Before,C.Strokes),'rejection preserves the complete legacy estimate');
          Row:=TJSONObject.Create; Rows.AddElement(Row); Row.AddPair('font',FontName); Row.AddPair('character',Text);
          Row.AddPair('accepted',TJSONBool.Create(Used)); Row.AddPair('reason',Info.Reason);
          Row.AddPair('mode',Info.Mode);
          Row.AddPair('beforeCount',TJSONNumber.Create(Length(B.Strokes))); Row.AddPair('afterCount',TJSONNumber.Create(Length(C.Strokes)));
          Row.AddPair('expectedCount',TJSONNumber.Create(Length(Reference.Variants[0])));
          Row.AddPair('variant',TJSONNumber.Create(Info.VariantIndex));
          Row.AddPair('beforeError',TJSONNumber.Create(Info.BeforeError)); Row.AddPair('afterError',TJSONNumber.Create(Info.AfterError));
          Row.AddPair('coverage',TJSONNumber.Create(Info.Coverage));
          Row.AddPair('recoveredComponents',TJSONNumber.Create(Info.RecoveredComponents));
          Row.AddPair('repairedEdges',TJSONNumber.Create(Info.RepairedEdges));
          Row.AddPair('adaptedGuide',TJSONBool.Create(Info.AdaptedGuide));
          if (Length(Reference.Variants)>1) or
            ((F<=2) and (Pos(Text,'あおきこなぬのシツソンノABCXYZaceg0124689')>0)) then
          begin
            Row.AddPair('width',TJSONNumber.Create(G.Width)); Row.AddPair('height',TJSONNumber.Create(G.Height));
            Row.AddPair('mask',TJSONString.Create(TNetEncoding.Base64.EncodeBytesToString(G.Mask)));
            Row.AddPair('before',PathsJSON(B)); Row.AddPair('after',PathsJSON(C));
          end;
        finally B.Free; C.Free end;
      end;
      Writeln('REFERENCE FONT ',FontName,' cumulative ',Accepted,'/',Total);
    end;
    // 参照のない文字は経路・露出・時間を完全に従来方式へ戻す。
    S:=DefaultWritingSettings; S.FontName:='ＭＳ ゴシック'; Engine.Configure(S);
    // 参照の照合スコアとは別に定めた、代表的な画数・筆記方向の期待値。
    for Text in TArray<string>.Create('A','X','i','ぬ','ソ') do
    begin
      G:=CloneShape(Engine.Glyph(Text));
      try
        InferGlyphStrokes(G);
        if Text='A' then
        begin
          Check(G.ReferenceUsed and (Length(G.Strokes)=3),'A: two downward diagonals followed by crossbar');
          P:=G.Strokes[0].Points[0]; Q:=G.Strokes[0].Points[High(G.Strokes[0].Points)];
          Check((Q.X<P.X) and (Q.Y>P.Y),'A: first diagonal starts at apex and descends left');
          P:=G.Strokes[1].Points[0]; Q:=G.Strokes[1].Points[High(G.Strokes[1].Points)];
          Check((Q.X>P.X) and (Q.Y>P.Y),'A: second diagonal descends right');
        end;
        if Text='X' then
        begin
          Check(G.ReferenceUsed and (Length(G.Strokes)=2),'X: retain two crossing strokes');
          P:=G.Strokes[1].Points[0]; Q:=G.Strokes[1].Points[High(G.Strokes[1].Points)];
          Check((Q.X<P.X) and (Q.Y>P.Y),'X: second stroke descends left across the intersection');
        end;
        if Text='i' then
        begin
          Check(G.ReferenceUsed and (Length(G.Strokes)=2),'i: body then dot');
          Check(G.Strokes[0].Points[0].Y>G.Strokes[1].Points[0].Y,'i: upper dot is written last');
        end;
        if Text='ぬ' then
        begin
          Check(G.ReferenceUsed and (Length(G.Strokes)=2),'nu: two strokes preserve the crossing and terminal loop');
          Check(G.Strokes[1].Points[0].X>G.Strokes[0].Points[0].X,'nu: right-hand descending stroke is second');
        end;
        if Text='ソ' then
        begin
          Check(Length(G.Strokes)=2,'so: two strokes'); P:=G.Strokes[1].Points[0]; Q:=G.Strokes[1].Points[High(G.Strokes[1].Points)];
          Check((Q.X<P.X) and (Q.Y>P.Y),'so: second stroke descends left');
        end;
      finally G.Free end;
    end;
    for Text in TArray<string>.Create('漢','永','。','Ω') do
    begin
      G:=Engine.Glyph(Text); B:=CloneShape(G); C:=CloneShape(G);
      try InferGlyphStrokes(B,False); InferGlyphStrokes(C);
        Check(SamePaths(B.Strokes,C.Strokes) and (B.TotalDistance=C.TotalDistance),'unknown fallback');
      finally B.Free; C.Free end;
    end;
    // 単一線へBを無理に当てはめない。参照でフォント形状を生成しない。
    G:=CloneShape(Engine.Glyph('l'));
    try G.Character:='B'; InferGlyphStrokes(G,False); Before:=G.Strokes;
      Check(not TryApplyStrokeReference(G,Info),'incompatible topology rejected'); Check(SamePaths(Before,G.Strokes),'mismatch fallback');
    finally G.Free end;
    // GUID専用学習で順序・方向・経路・空の学習の最優先を確認する。
    ID:=StringReplace(StringReplace(StringReplace(TGUID.NewGuid.ToString,'{','',[]),'}','',[]),'-','',[rfReplaceAll]); ID:=LowerCase(ID+ID);
    G:=CloneShape(Engine.Glyph('シ')); Loaded:=CloneShape(G); G.FontID:=ID; Loaded.FontID:=ID;
    Folder:=TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),ID);
    try
      InferGlyphStrokes(G); ReverseGlyphStroke(G,0); SaveGlyphLearning(G);
      Check(LoadGlyphLearning(Loaded,Warning) and (Warning='') and Loaded.Learned,'user learning reload');
      Before:=Loaded.Strokes; Check(not TryApplyStrokeReference(Loaded,Info),'user learning overrides reference');
      Check(SamePaths(G.Strokes,Loaded.Strokes) and SamePaths(Before,Loaded.Strokes),'manual direction preserved');
      G.Strokes:=nil; SaveGlyphLearning(G); Check(LoadGlyphLearning(Loaded,Warning) and Loaded.Learned and (Length(Loaded.Strokes)=0),'empty manual learning priority');
    finally
      DeleteGlyphLearning(G,False); G.Free; Loaded.Free;
      if TDirectory.Exists(Folder) then TDirectory.Delete(Folder,False);
    end;
    // 本番AUF2のRGBAを共有描画器と比較。完成字形・逆シーク・重複文字も確認する。
    S:=DefaultWritingSettings; S.FontName:='ＭＳ ゴシック'; S.FontSize:=60; S.ShowPen:=False;
    for Text in TArray<string>.Create('あおあお','きぎさざき','シツソンノ','かなカナかな','ABCXYZ','abcxyz','0123456789','わをんん','いい','えぇえ','けかがげゕゖ','てでて','なねなね','ふほふほ','むもむも','ゐゆゑ','りれりれ','アア','タネムゥヒヒ','ijij bdpq','EAFH KLMN PRTV WXY A') do
    begin
      if Text='いい' then S.FontName:='游明朝';
      S.ShowPen:=(Text='わをんん') or (Text='タネムゥヒヒ') or (Text='ijij bdpq') or (Text='EAFH KLMN PRTV WXY A');
      S.Text:=Text; Context.Configure(S); Context.SizeFrame(800,320); Context.Renderer.Prepare(S);
      for J:=0 to 3 do
      begin
        case J of 0: ErrorBefore:=Context.Renderer.Duration(S)*0.35; 1: ErrorBefore:=Context.Renderer.Duration(S)*0.75; 2: ErrorBefore:=10000; else ErrorBefore:=0.1 end;
        Pixels:=Context.Render(ErrorBefore); Context.Renderer.Render(nil,800,320,ErrorBefore,S,Expected);
        Check((Length(Pixels)=Length(Expected)) and CompareMem(@Pixels[0],@Expected[0],Length(Pixels)*4),'production frames, completion and reverse seek');
      end;
      Context.SavePNG(Pixels,800,320,'reference_'+IntToHex(Ord(Text[1]),4)+'.png');
    end;
    Summary:=TJSONObject.Create;
    try
      Summary.AddPair('cases',TJSONNumber.Create(Total)); Summary.AddPair('accepted',TJSONNumber.Create(Accepted));
      Summary.AddPair('orderOnly',TJSONNumber.Create(OrderOnly));
      Summary.AddPair('trimmed',TJSONNumber.Create(Trimmed));
      Summary.AddPair('hiraganaAccepted',TJSONNumber.Create(Hira)); Summary.AddPair('katakanaAccepted',TJSONNumber.Create(Kata)); Summary.AddPair('latinAccepted',TJSONNumber.Create(Latin));
      Summary.AddPair('countCorrectBefore',TJSONNumber.Create(CountBefore)); Summary.AddPair('countCorrectAfter',TJSONNumber.Create(CountAfter));
      Summary.AddPair('existingLearnedReadOnly',TJSONNumber.Create(Learned));
      TFile.WriteAllText(TPath.Combine(OutputDirectory,'ReferenceSummary.json'),Summary.ToJSON,TEncoding.UTF8);
      TFile.WriteAllText(TPath.Combine(OutputDirectory,'ReferenceCases.json'),Rows.ToJSON,TEncoding.UTF8);
    finally Summary.Free end;
    Check((Hira>0) and (Kata>0) and (Latin>0),'all target categories improve'); Check(CountAfter>=CountBefore,'stroke count does not regress');
    Writeln('PASS stroke reference ',Accepted,'/',Total,'; correct counts ',CountBefore,' -> ',CountAfter);
  finally Rows.Free; Engine.Free end;
end;

end.
