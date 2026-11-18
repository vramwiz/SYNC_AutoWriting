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

procedure TestStrokeReferences(const Context: TPenTestContext; const OutputDirectory: string);
var Engine: TWritingFontEngine; S: TWritingSettings; G,B,C,Loaded: TWritingGlyph;
  Reference: TStrokeReference; Info: TReferenceFitInfo; Rows: TJSONArray; Row,Summary: TJSONObject;
  Mask: TBytes; Before: TArray<TStroke>; Code: Cardinal; FontName,Text,ID,Folder,Warning: string;
  I,J,K,F,Total,Accepted,Hira,Kata,Latin,CountBefore,CountAfter,Learned,OrderOnly: Integer;
  Used,Found: Boolean; P,Q: TPointF; ErrorBefore: Double; Pixels,Expected: TWritingPixels;
  procedure Check(OK: Boolean; const MessageText: string);
  begin Context.Check(OK,'Reference: '+MessageText) end;
begin
  TestFontListAndWheel(Context); TestReferenceOrderFallback(Context); TestPreviewContrast(Context); Check(StrokeReferenceCount=238,'238 character coverage');
  for I:=0 to StrokeReferenceCount-1 do
  begin
    Code:=StrokeReferenceCodepoint(I); if I>0 then Check(Code>StrokeReferenceCodepoint(I-1),'sorted unique index');
    Check(FindStrokeReference(Code,Reference),'index lookup');
    for J:=0 to High(Reference.Strokes) do
    begin
      Check(Length(Reference.Strokes[J].Points)>=2,'path endpoints');
      for P in Reference.Strokes[J].Points do Check((P.X>=0) and (P.X<=1) and (P.Y>=0) and (P.Y<=1),'normal coordinates');
    end;
  end;
  Check(not FindStrokeReference(Ord('漢'),Reference),'kanji is future work');
  Check(not FindStrokeReference($1F600,Reference),'unknown supplementary codepoint');
  Engine:=TWritingFontEngine.Create; Rows:=TJSONArray.Create;
  Total:=0; Accepted:=0; Hira:=0; Kata:=0; Latin:=0; CountBefore:=0; CountAfter:=0; Learned:=0; OrderOnly:=0;
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
          Check(Length(C.Mask)=Length(Mask),'mask length unchanged');
          Check(CompareMem(@Mask[0],@C.Mask[0],Length(Mask)),'font shape unchanged');
          FindStrokeReference(Code,Reference);
          if Length(B.Strokes)=Length(Reference.Strokes) then Inc(CountBefore);
          if Length(C.Strokes)=Length(Reference.Strokes) then Inc(CountAfter);
          if Used then
          begin
            Inc(Accepted); if Code<$80 then Inc(Latin) else if Code<$30A0 then Inc(Hira) else Inc(Kata);
            Check(Info.Coverage>=0.92,'skeleton coverage');
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
            else Check(Info.AfterError+0.75<Info.BeforeError,'clear ordered improvement');
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
          Row.AddPair('expectedCount',TJSONNumber.Create(Length(Reference.Strokes)));
          Row.AddPair('beforeError',TJSONNumber.Create(Info.BeforeError)); Row.AddPair('afterError',TJSONNumber.Create(Info.AfterError));
          Row.AddPair('coverage',TJSONNumber.Create(Info.Coverage));
          Row.AddPair('recoveredComponents',TJSONNumber.Create(Info.RecoveredComponents));
          Row.AddPair('repairedEdges',TJSONNumber.Create(Info.RepairedEdges));
          Row.AddPair('adaptedGuide',TJSONBool.Create(Info.AdaptedGuide));
          if (F<=2) and (Pos(Text,'あおきこなぬのシツソンノABCXYZaceg0124689')>0) then
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
    for Text in TArray<string>.Create('あおあお','シツソンノ','かなカナかな','ABCXYZ','abcxyz','0123456789') do
    begin
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
