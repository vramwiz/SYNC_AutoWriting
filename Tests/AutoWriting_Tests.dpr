program AutoWriting_Tests;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 本番AUF2を実際に読み込み、フレーム描画・SDK登録・元フォント形状を検査する。
// 学習IOは一意なIDまたは未使用の私用文字を使い、既存のユーザーデータへ書き込まない。

{$APPTYPE CONSOLE}
{$R+}{$Q+}

uses System.SysUtils, System.Classes, System.Math, System.Types, System.Hash,
  System.IOUtils, System.Diagnostics, Winapi.Windows, Winapi.Messages, Winapi.CommCtrl, Vcl.Graphics, Vcl.Imaging.pngimage,
  AviUtl2FilterTypes in '..\Source\Lib\AviUtl2FilterTypes.pas',
  AutoWriting_Types in '..\Source\Common\AutoWriting_Types.pas',
  AutoWriting_Vertices in '..\Source\Common\AutoWriting_Vertices.pas',
  AutoWriting_Branches in '..\Source\Common\AutoWriting_Branches.pas',
  AutoWriting_Reveal in '..\Source\Common\AutoWriting_Reveal.pas',
  AutoWriting_Inference in '..\Source\Common\AutoWriting_Inference.pas',
  AutoWriting_Editing in '..\Source\Common\AutoWriting_Editing.pas',
  AutoWriting_Learning in '..\Source\Common\AutoWriting_Learning.pas',
  AutoWriting_Fonts in '..\Source\Common\AutoWriting_Fonts.pas',
  AutoWriting_Renderer in '..\Source\Common\AutoWriting_Renderer.pas',
  AutoWriting_PenTests in 'AutoWriting_PenTests.pas';

type
  TGetTable = function: PFILTER_PLUGIN_TABLE; cdecl;
  TInitialize = function(Version: Cardinal): Byte; cdecl;
  TRequired = function: Cardinal; cdecl;
  TUninitialize = procedure; cdecl;
  PItem = ^TItem;
  TItem = record ItemType,Name: PWideChar end;

function PrintWindow(Wnd: HWND; DC: HDC; Flags: UINT): BOOL; stdcall; external 'user32.dll';

var
  Table: PFILTER_PLUGIN_TABLE;
  TextItem,DetailsItem: PFILTER_ITEM_STRING;
  PenItem: PFILTER_ITEM_SELECT;
  Tracks: array[0..8] of PFILTER_ITEM_TRACK;
  Button: PFILTER_ITEM_BUTTON;
  Video: TFILTER_PROC_VIDEO; Obj: TOBJECT_INFO; Scene: TSCENE_INFO;
  Captured,HostInput: TWritingPixels;
  TextBacking,DetailBacking,OutputDirectory: string;
  Renderer: TWritingRenderer;
  SetCount,Tests: Integer;
  DialogHandle,MemoHandle,PageHandle,PenHandle,AngleHandle,ApplyHandle: HWND;
  LightXHandle,LightYHandle: HWND;
  PenSizeHandle: HWND;
  ChangeAngleInDialog: Boolean;
  PreviewSurface,EditorSurface: HWND;
  UITimer: UINT_PTR;
  UIStage,UICount,UIEdits,DialogPenChoice: Integer;
  UIError: string;
  UIValues: array[0..7] of UTF8String;
  EditingTimer: UINT_PTR;
  EditingStage,EditingTicks,EditingInitialCount: Integer;
  EditingStrokeList: HWND;
  EditingError,EditingFile: string;
  EditingPoint: TPoint;
  EditingGlyphPoint: TPointF;
  EditingGlyphSecondPoint: TPointF;
  EditingSecondPoint: TPoint;
  EditingGlyphWidth,EditingGlyphHeight,EditingSelectedStroke: Integer;
  EditingFontID,EditingCharacter: string;
  EditingFirst,EditingLast,EditingNormal: TPointF;
  PopupWindow: HWND;
  EditingDragCapture: HWND;
  EditingDragPosition: LPARAM;
  EditingBeforeDragHash: string;
  BranchTimer: UINT_PTR;
  BranchStage,BranchTicks: Integer;
  BranchFile,BranchError,BranchFontID,BranchCharacter,BranchBeforeHash: string;
  BranchWidth,BranchHeight: Integer;

procedure Check(Condition: Boolean; const MessageText: string);
begin Inc(Tests); if not Condition then raise Exception.Create(MessageText) end;

function Same(const A,B: TWritingPixels): Boolean;
begin Result:=(Length(A)=Length(B)) and ((Length(A)=0) or CompareMem(@A[0],@B[0],Length(A)*4)) end;

procedure GetImage(Buffer: PPIXEL_RGBA); cdecl;
begin
  if Length(HostInput)>0 then Move(HostInput[0],Buffer^,Length(HostInput)*4)
  else FillChar(Buffer^,Obj.Width*Obj.Height*4,0);
end;

procedure SetImage(Buffer: PPIXEL_RGBA; Width,Height: Integer); cdecl;
begin
  Inc(SetCount); Check((Width=Scene.Width) and (Height=Scene.Height),'Unexpected frame size');
  SetLength(Captured,Width*Height); Move(Buffer^,Captured[0],Length(Captured)*4);
end;

procedure SizeFrame(W,H: Integer);
begin Scene.Width:=W; Scene.Height:=H; Obj.Width:=W; Obj.Height:=H; HostInput:=nil end;

procedure Configure(const S: TWritingSettings);
begin
  TextBacking:=EncodeHostText(S.Text); DetailBacking:=SettingsJSON(S);
  TextItem^.Value:=PChar(TextBacking); DetailsItem^.Value:=PChar(DetailBacking);
  Tracks[0]^.Value:=S.X; Tracks[1]^.Value:=S.Y; Tracks[2]^.Value:=S.Scale;
  Tracks[3]^.Value:=S.Transparency; Tracks[4]^.Value:=S.Speed; Tracks[5]^.Value:=S.PenAngle; PenItem^.Value:=PenChoiceValue(S.Pen);
  Tracks[6]^.Value:=S.LightX; Tracks[7]^.Value:=S.LightY;
  Tracks[8]^.Value:=S.PenSize*100;
end;

function Render(Time: Double): TWritingPixels;
var Count: Integer;
begin
  Obj.Time:=Time; Count:=SetCount;
  Check(Table^.Func_Proc_Video(@Video)=1,'Production render failed at '+FloatToStr(Time));
  Check(SetCount=Count+1,'Missing output callback'); Result:=Copy(Captured);
end;

function Coverage(const A: TWritingPixels): Integer;
var P: TPIXEL_RGBA;
begin Result:=0; for P in A do if P.A>0 then Inc(Result) end;

procedure SavePNG(const A: TWritingPixels; W,H: Integer; const FileName: string);
var PNG: TPngImage; X,Y,I: Integer; Row: PByte;
begin
  PNG:=TPngImage.CreateBlank(COLOR_RGBALPHA,8,W,H);
  try
    for Y:=0 to H-1 do
    begin
      Row:=PNG.Scanline[Y];
      for X:=0 to W-1 do
      begin
        I:=Y*W+X; Row[X*3]:=A[I].B; Row[X*3+1]:=A[I].G;
        Row[X*3+2]:=A[I].R; PNG.AlphaScanline[Y]^[X]:=A[I].A;
      end;
    end;
    PNG.SaveToFile(TPath.Combine(OutputDirectory,FileName));
  finally PNG.Free end;
end;

procedure Bind;
var P: PPointer; I,N: Integer; Name: string; Choice: ^TFILTER_ITEM_SELECT_ITEM;
begin
  P:=PPointer(Table^.Items); N:=0;
  while P^<>nil do
  begin
    Inc(N); Check(N<30,'Unterminated parameters'); Name:=PItem(P^)^.Name;
    if Name='表示文字列' then TextItem:=PFILTER_ITEM_STRING(P^);
    if Name='詳細設定' then if string(PItem(P^)^.ItemType)='string' then DetailsItem:=PFILTER_ITEM_STRING(P^);
    if Name='ペン種類' then PenItem:=PFILTER_ITEM_SELECT(P^);
    if Name='設定' then Button:=PFILTER_ITEM_BUTTON(P^);
    if Name='X座標' then Tracks[0]:=PFILTER_ITEM_TRACK(P^);
    if Name='Y座標' then Tracks[1]:=PFILTER_ITEM_TRACK(P^);
    if Name='拡大率' then Tracks[2]:=PFILTER_ITEM_TRACK(P^);
    if Name='透明度' then Tracks[3]:=PFILTER_ITEM_TRACK(P^);
    if Name='ペン速度' then Tracks[4]:=PFILTER_ITEM_TRACK(P^);
    if Name='ペン角度' then Tracks[5]:=PFILTER_ITEM_TRACK(P^);
    if Name='光源X' then Tracks[6]:=PFILTER_ITEM_TRACK(P^);
    if Name='光源Y' then Tracks[7]:=PFILTER_ITEM_TRACK(P^);
    if Name='ペンサイズ' then Tracks[8]:=PFILTER_ITEM_TRACK(P^);
    Inc(P);
  end;
  Check(N=14,'Expected 12 visible parameters plus hidden details and hiding rule');
  Check((TextItem<>nil) and (DetailsItem<>nil) and (PenItem<>nil) and (Button<>nil),'Missing parameters');
  for I:=0 to 8 do Check(Tracks[I]<>nil,'Missing track');
  Check((Tracks[8]^.Value=100) and (Abs(Tracks[8]^.Step-0.01)<1E-12),'Pen size must default to 100 with step 0.01');
  Check(Assigned(Button^.Callback2),'Settings callback missing');
  Check(PenItem^.Value=2,'Existing fountain default ID must stay 2'); Choice:=Pointer(PenItem^.List);
  for I:=0 to 5 do begin
    Check((Choice^.Name<>nil) and (string(Choice^.Name)=string(AW_PEN_NAMES[AW_PEN_ORDER[I]])) and
      (Choice^.Value=PenChoiceValue(AW_PEN_ORDER[I])),'Pen display order or stored ID mismatch');
    if I>0 then Check(Choice^.Value>PenChoiceValue(AW_PEN_ORDER[I-1]),'Host identifier order must match the display order'); Inc(Choice);
  end;
  Check(Choice^.Name=nil,'Pen list must have six choices and a nil terminator');
end;

procedure TestSettingsAndLearning;
var S,R: TWritingSettings; Text,Warning,ID,FileName,Folder: string;
  G,Reloaded: TWritingGlyph; I: Integer; Before: TPointF; Characters: TArray<string>; OriginalDistance: Double;
begin
  S:=DefaultWritingSettings; Text:='一\n二'+sLineBreak+'\日本語';
  Check(DecodeHostText(EncodeHostText(Text))=Text,'Host newline/backslash roundtrip');
  S.FontName:='ＭＳ 明朝'; S.Vertical:=True; S.Ratios[ckHiragana]:=0.75; S.PenAngle:=45;
  R:=DefaultWritingSettings; ReadSettingsJSON(SettingsJSON(S),R);
  Check((R.FontName=S.FontName) and R.Vertical and (R.Ratios[ckHiragana]=0.75) and (R.PenAngle=45),'Settings persistence');
  S.LightX:=120.25; S.LightY:=-180.75; ReadSettingsJSON(SettingsJSON(S),R);
  Check((R.LightX=S.LightX) and (R.LightY=S.LightY),'Light XY persistence');
  R:=DefaultWritingSettings; ReadSettingsJSON('{"schema":1,"penAngle":-35}',R);
  Check((R.LightX=-100) and (R.LightY=-100),'Old settings must use default lighting');
  R:=S; ReadSettingsJSON('{broken',R); Check(R.FontName=S.FontName,'Malformed settings changed font');
  Characters:=UnicodeCharacters('あ'+#$D842#$DFB7+sLineBreak+'い');
  Check((Length(Characters)=4) and (Length(Characters[1])=2) and (Characters[2]=#10),'Unicode/newline split');
  ID:=THashSHA2.GetHashString('AutoWriting verification '+TGUID.NewGuid.ToString);
  G:=TWritingGlyph.Create; Reloaded:=TWritingGlyph.Create;
  Folder:=TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),ID); FileName:=TPath.Combine(Folder,'691C.json');
  try
    G.FontID:=ID; G.FontFace:='Verification synthetic'; G.Character:='検'; G.Width:=12; G.Height:=12;
    SetLength(G.Mask,144); FillChar(G.Mask[0],144,255); SetLength(G.Strokes,2);
    for I:=0 to 1 do
    begin
      G.Strokes[I].ID:=I; SetLength(G.Strokes[I].Points,2);
      G.Strokes[I].Points[0]:=PointF(2,I*6+2); G.Strokes[I].Points[1]:=PointF(9,I*6+2);
    end;
    SetLength(G.Strokes[0].Points,3); G.Strokes[0].Points[1]:=PointF(5,2); G.Strokes[0].Points[2]:=PointF(9,2);
    PrepareGlyphTiming(G); OriginalDistance:=G.TotalDistance;
    Check(SplitGlyphStroke(G,0,1) and (Length(G.Strokes)=3),'Split at interior point');
    Check(MergeGlyphStrokes(G,0) and (Length(G.Strokes)=2),'Merge adjacent strokes');
    Check((Length(G.Strokes[0].Points)=3) and (Abs(G.TotalDistance-OriginalDistance)<1E-6),'Split/merge geometry roundtrip');
    Check(not SplitGlyphStroke(G,0,0),'Split at endpoint should be rejected');
    Before:=G.Strokes[0].Points[0];
    ReverseGlyphStroke(G,0); MoveGlyphStroke(G,0,1); SaveGlyphLearning(G);
    Reloaded.FontID:=ID; Reloaded.Character:='検'; Reloaded.Width:=12; Reloaded.Height:=12; Reloaded.Mask:=Copy(G.Mask);
    Check(LoadGlyphLearning(Reloaded,Warning) and (Warning=''),'Learning reload');
    Check((Reloaded.Strokes[1].ID=0) and Reloaded.Strokes[1].Reversed,'Learning order/direction');
    Check(Reloaded.Strokes[1].Points[High(Reloaded.Strokes[1].Points)]=Before,'Learning coordinates');
    Text:=TFile.ReadAllText(FileName);
    Check((Pos('mask',LowerCase(Text))=0) and (Pos('outline',LowerCase(Text))=0),'Learning contains font source');
    TFile.WriteAllText(FileName,'{"schema":1,"strokes":[]}',TEncoding.UTF8);
    Check(not LoadGlyphLearning(Reloaded,Warning) and (Warning<>''),'Malformed learning not rejected');
    Check(TFile.ReadAllText(FileName)='{"schema":1,"strokes":[]}','Malformed learning overwritten');
  finally
    Reloaded.Free; G.Free;
    if TFile.Exists(FileName) then TFile.Delete(FileName);
    if TDirectory.Exists(Folder) then TDirectory.Delete(Folder,False);
  end;
  Writeln('PASS settings, Unicode, learning save/reload, corrupt-data preservation');
end;

procedure TestStrokeEditing;
var G,Reloaded,Other: TWritingGlyph; State,Edited: TGlyphEditState; Hit: TStrokeHit;
  I,AStart,BStart,JoinedIndex,J,K,SplitIndex: Integer; Engine: TWritingFontEngine;
  S: TWritingSettings; Mask: TBytes; ID,Folder,FileName,Warning: string;
  StartPoint,EndPoint,Junction: TPointF; LengthBefore: Double;
begin
  G:=TWritingGlyph.Create;
  try
    G.Width:=20; G.Height:=20; SetLength(G.Mask,400); FillChar(G.Mask[0],400,255);
    SetLength(G.Strokes,3);
    for I:=0 to 2 do
    begin
      G.Strokes[I].ID:=I; SetLength(G.Strokes[I].Points,2);
      G.Strokes[I].Points[0]:=PointF(2,I*6+2); G.Strokes[I].Points[1]:=PointF(12,I*6+2);
    end;
    PrepareGlyphTiming(G); State:=CaptureGlyphState(G); Mask:=Copy(G.Mask);
    Hit:=HitStroke(G,PointF(6.25,2.4),1,0);
    Check((Hit.Stroke=0) and (Abs(Hit.Point.X-6.25)<1E-5),'Split hit must project onto a segment');
    Check(SplitStrokeAt(G,Hit) and (Length(G.Strokes)=4),'Split between existing control points');
    Check(Abs(G.Strokes[0].Points[High(G.Strokes[0].Points)].X-6.25)<1E-5,'Interpolated split position');
    Check(Distance(G.Strokes[1].Points[0],G.Strokes[0].Points[High(G.Strokes[0].Points)])<1E-5,'Split endpoints must coincide');
    Check(State.Strokes[0].Points[1]=PointF(12,2),'Split changed an undo snapshot');
    Hit:=HitEndpoint(G,PointF(6.25,2),1,0,0);
    Check(Hit.Stroke=1,'Shared endpoint must allow selecting the other stroke');
    Check(JoinStrokeEndpoints(G,0,False,1,True,JoinedIndex),'Rejoin split halves');
    Check((JoinedIndex=0) and (Length(G.Strokes)=3),'Rejoin stroke count');
    for AStart:=0 to 1 do for BStart:=0 to 1 do
    begin
      RestoreGlyphState(G,State); StartPoint:=G.Strokes[0].Points[AStart];
      EndPoint:=G.Strokes[2].Points[BStart];
      Check(JoinStrokeEndpoints(G,0,AStart<>0,2,BStart<>0,JoinedIndex),'Join nonadjacent strokes');
      Check(G.Strokes[JoinedIndex].Points[0]=StartPoint,'Join oriented first stroke incorrectly');
      Check(G.Strokes[JoinedIndex].Points[High(G.Strokes[JoinedIndex].Points)]=EndPoint,'Join oriented second stroke incorrectly');
      Check(G.Strokes[1].ID=1,'Join discarded an unrelated stroke');
    end;
    RestoreGlyphState(G,State);
    Check(JoinStrokeEndpoints(G,2,False,0,True,JoinedIndex) and (JoinedIndex=1),'Join to an earlier list row');
    Edited:=CaptureGlyphState(G); ReverseGlyphStroke(G,0);
    RestoreGlyphState(G,Edited); Check(G.Strokes[0].Points[0]=Edited.Strokes[0].Points[0],'Deep undo snapshot');
    RestoreGlyphState(G,State); Check(Length(G.Strokes)=3,'Undo stroke count');
    Check(not JoinStrokeEndpoints(G,0,False,0,True,JoinedIndex),'Self-join should be rejected');
    Check(CompareMem(@Mask[0],@G.Mask[0],Length(Mask)),'Editing changed the original font mask');
  finally G.Free end;

  // 報告された「自」で、上の短い画を接続箇所から切り離せることを実字形で確認する。
  Engine:=TWritingFontEngine.Create; Other:=TWritingGlyph.Create; Reloaded:=TWritingGlyph.Create;
  ID:=THashSHA2.GetHashString('Stroke editing verification '+TGUID.NewGuid.ToString);
  Folder:=TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),ID); FileName:=TPath.Combine(Folder,'81EA.json');
  try
    S:=DefaultWritingSettings; Engine.Configure(S); G:=Engine.Glyph('自'); InferGlyphStrokes(G); G.Learned:=False;
    State:=CaptureGlyphState(G); LengthBefore:=G.Strokes[0].Length;
    SetLength(Other.Strokes,Length(G.Strokes)-1);
    for I:=1 to High(G.Strokes) do Other.Strokes[I-1]:=G.Strokes[I];
    SplitIndex:=-1; Junction:=PointF(0,0);
    for J:=1 to High(G.Strokes[0].Points)-1 do
    begin
      Hit:=HitStroke(Other,G.Strokes[0].Points[J],0.25,-1);
      if Hit.Stroke>=0 then begin SplitIndex:=J; Junction:=G.Strokes[0].Points[J]; Break end;
    end;
    Check(SplitIndex>0,'Actual 自 has no testable shared junction');
    Hit:=HitStroke(G,Junction,0.5,0); Check(Hit.Stroke=0,'Selected first stroke must win at an intersection');
    Check(SplitStrokeAt(G,Hit),'Cannot separate first stroke of 自');
    Check(G.Strokes[0].Length<LengthBefore*0.5,'First stroke of 自 is still joined to the frame');
    Check(Length(G.Strokes)=Length(State.Strokes)+1,'自 split did not add a separate stroke');
    G.FontID:=ID; SaveGlyphLearning(G); Edited:=CaptureGlyphState(G);
    Reloaded.FontID:=ID; Reloaded.Character:='自'; Reloaded.Width:=G.Width; Reloaded.Height:=G.Height; Reloaded.Mask:=Copy(G.Mask);
    Check(LoadGlyphLearning(Reloaded,Warning) and (Warning=''),'Split learning did not reload');
    Check(Length(Reloaded.Strokes)=Length(Edited.Strokes),'Split learning lost a stroke');
    RestoreGlyphState(G,State); DeleteGlyphLearning(G,False);
    Check(not TFile.Exists(FileName) and not G.Learned,'Undo to inferred state left learning behind');
    RestoreGlyphState(G,Edited); SaveGlyphLearning(G);
    Check(TFile.Exists(FileName) and G.Learned,'Redo did not restore saved learning');
    for I:=0 to High(State.Strokes) do for K:=0 to High(State.Strokes[I].Points) do
      Check((State.Strokes[I].Points[K].X>=0) and (State.Strokes[I].Points[K].Y>=0),'Snapshot coordinates corrupted');
    Writeln('PASS click-to-split, all endpoint orientations, nonadjacent join, undo/redo, actual 自 and learning');
  finally
    Reloaded.Free; Other.Free; Engine.Free;
    if TFile.Exists(FileName) then TFile.Delete(FileName);
    if TDirectory.Exists(Folder) then TDirectory.Delete(Folder,False);
  end;
end;

procedure TestEditingVertices;
var G,Loaded: TWritingGlyph; State: TGlyphEditState; Hit: TStrokeHit; Original: TStroke;
  Vertices,HitPoints: TArray<Integer>; Hits: TArray<TStrokeHit>; Reveal: TArray<Single>;
  I,Index,Joined: Integer; Before: Double;
  Folder,FileName,Warning: string;
begin
  G:=TWritingGlyph.Create; Loaded:=TWritingGlyph.Create; Folder:='';
  try
    G.Width:=64; G.Height:=48; G.Character:='頂';
    G.FontID:=THashSHA2.GetHashString('Sparse editing vertices '+TGUID.NewGuid.ToString);
    Folder:=TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),G.FontID); FileName:=TPath.Combine(Folder,'9802.json');
    SetLength(G.Mask,64*48); for I:=0 to 50 do G.Mask[20*64+I]:=255;
    SetLength(G.Strokes,1); SetLength(G.Strokes[0].Points,51);
    for I:=0 to 50 do G.Strokes[0].Points[I]:=PointF(I,20);
    PrepareGlyphTiming(G); Before:=G.TotalDistance; Reveal:=Copy(G.Reveal);
    Vertices:=EditingVertices(G.Strokes[0]);
    Check((Length(Vertices)=2) and (Vertices[0]=0) and (Vertices[1]=50),'Straight path must expose only its endpoints');
    Check(Length(G.Strokes[0].Points)=51,'Editing handle reduction discarded rendering samples');
    Hit:=HitStroke(G,PointF(25.5,20),1,0); State:=CaptureGlyphState(G);
    Check(CreateStrokeVertex(G,Hit,Index),'Cannot create a vertex on a sparse straight path');
    Check((Index=26) and (G.Strokes[0].Points[Index]=PointF(25.5,20)),'Created vertex is not at the requested line position');
    Vertices:=EditingVertices(G.Strokes[0]); Check(Length(Vertices)=3,'Created collinear vertex was hidden');
    Check(Abs(G.TotalDistance-Before)<1E-6,'Creating a collinear vertex changed writing time');
    for I:=0 to High(Reveal) do Check(Abs(G.Reveal[I]-Reveal[I])<1E-5,'Creating a vertex changed the original reveal');
    Check(Length(State.Strokes[0].Points)=51,'Vertex insertion changed the undo snapshot');
    SaveGlyphLearning(G); Loaded.FontID:=G.FontID; Loaded.Character:=G.Character;
    Loaded.Width:=G.Width; Loaded.Height:=G.Height;
    Check(LoadGlyphLearning(Loaded,Warning) and (Warning=''),'Pinned vertex did not reload');
    Check((Length(Loaded.Strokes[0].PinnedVertices)=1) and (Loaded.Strokes[0].PinnedVertices[0]=Index),'Learning lost a pinned vertex');
    State:=CaptureGlyphState(G); Original:=State.Strokes[0];
    Check(MovePathVertex(Original,Index,PointF(25.5,26),G.Strokes[0]),'Cannot move a sparse editing vertex');
    Check((G.Strokes[0].Points[0]=PointF(0,20)) and (G.Strokes[0].Points[High(G.Strokes[0].Points)]=PointF(50,20)),
      'Moving an interior vertex moved its neighboring anchors');
    Check((G.Strokes[0].Points[Index-1].Y>25) and (G.Strokes[0].Points[Index+1].Y>25),'Moving a vertex left an isolated spike');
    for I:=0 to High(Original.Points) do Check(Original.Points[I].Y=20,'Deformation mutated the original path');
    RestoreGlyphState(G,State); ReverseGlyphStroke(G,0);
    Check(G.Strokes[0].Points[G.Strokes[0].PinnedVertices[0]]=PointF(25.5,20),'Reverse lost the physical pinned vertex');
    ReverseGlyphStroke(G,0); Check(G.Strokes[0].PinnedVertices[0]=Index,'Reverse roundtrip lost vertex index');
    Check(SplitGlyphStroke(G,0,Index),'Cannot split at a created vertex');
    Check((G.Strokes[0].PinnedVertices[0]=High(G.Strokes[0].Points)) and (G.Strokes[1].PinnedVertices[0]=0),
      'Split did not remap both copies of the pinned endpoint');
    Check(JoinStrokeEndpoints(G,0,False,1,True,Joined),'Cannot rejoin vertex split');
    Check((Length(G.Strokes[0].PinnedVertices)=1) and (G.Strokes[0].PinnedVertices[0]=Index),'Join duplicated or misplaced the vertex');
    G.Strokes[0].PinnedVertices[0]:=0;
    Check(State.Strokes[0].PinnedVertices[0]=Index,'Vertex metadata is shared with undo history');
    Original:=Default(TStroke); Original.Points:=[PointF(0,0),PointF(8,0),PointF(8,8),PointF(0,8),PointF(0,0)];
    Vertices:=EditingVertices(Original); Check(Length(Vertices)=5,'Closed path lost its corners');
    G.Strokes:=nil; SetLength(G.Strokes,2);
    G.Strokes[0].Points:=[PointF(0,10),PointF(20,10)];
    G.Strokes[1].Points:=[PointF(10,10),PointF(10,20)];
    Hits:=HitEditingPaths(G,PointF(10,10),0.5,0.75,HitPoints);
    Check((Length(Hits)=2) and (Hits[0].Stroke=1) and (HitPoints[0]=0) and
      (Hits[1].Stroke=0) and (HitPoints[1]=-1),'Another stroke endpoint hid an unanchored crossing line');
    Check(SplitStrokeAt(G,Hits[1]) and (Length(G.Strokes)=3),'Cannot split a sparse line at another stroke endpoint');
    SetLength(G.Strokes,1); G.Strokes[0]:=Default(TStroke);
    G.Strokes[0].Points:=[PointF(0,0),PointF(10,10),PointF(0,10),PointF(10,0)];
    Hits:=HitEditingPaths(G,PointF(5,5),0.5,0.75,HitPoints);
    Check((Length(Hits)=2) and (Hits[0].Segment=0) and (Hits[1].Segment=2),'Self-intersection must retain both line positions');
    Writeln('PASS sparse straight handles, exact line vertex, continuous deformation, learning and vertex remapping');
  finally
    Loaded.Free; G.Free;
    if (Folder<>'') and TFile.Exists(FileName) then TFile.Delete(FileName);
    if (Folder<>'') and TDirectory.Exists(Folder) then TDirectory.Delete(Folder,False);
  end;
end;

procedure TestOverlappingReveal;
var G: TWritingGlyph; X,Y: Integer; Mask: TBytes; FirstEnd: Double;
begin
  G:=TWritingGlyph.Create;
  try
    G.Width:=41; G.Height:=41; SetLength(G.Mask,41*41);
    for Y:=8 to 14 do for X:=3 to 37 do G.Mask[Y*41+X]:=255;
    for Y:=3 to 37 do for X:=17 to 23 do G.Mask[Y*41+X]:=255;
    SetLength(G.Strokes,2); SetLength(G.Strokes[0].Points,2); SetLength(G.Strokes[1].Points,2);
    G.Strokes[0].Points[0]:=PointF(3,11); G.Strokes[0].Points[1]:=PointF(37,11);
    G.Strokes[1].Points[0]:=PointF(20,3); G.Strokes[1].Points[1]:=PointF(20,37);
    Mask:=Copy(G.Mask); PrepareGlyphTiming(G); FirstEnd:=G.Strokes[0].Length;
    // 後続の縦画に近い画素も、先に書いた横画の領域から引かない。
    for Y:=8 to 14 do for X:=3 to 37 do
      Check(G.Reveal[Y*41+X]<=FirstEnd+1E-5,'Intersection left a hole in the completed horizontal stroke');
    Check(G.Reveal[30*41+20]>FirstEnd,'A distant future stroke appeared too early');
    // 円形に広げると交差部の幅が膨らみ、未筆記の縦画が上下に点として見えてしまう。
    for Y:=3 to 37 do if (Y<8) or (Y>14) then
      for X:=17 to 23 do Check(G.Reveal[Y*41+X]>FirstEnd,'Future vertical arm leaked outside the horizontal transfer region');
    Check(CompareMem(@Mask[0],@G.Mask[0],Length(Mask)),'Reveal generation modified the original font mask');
    Check(Abs(G.Strokes[0].Length-34)<1E-6,'Reveal generation changed writing distance');
    // 明朝のように横画が細く縦画が太い場合、近い中心線だけでは縦画の外側が横画へ漏れる。
    FillChar(G.Mask[0],Length(G.Mask),0);
    for Y:=9 to 11 do for X:=3 to 37 do G.Mask[Y*41+X]:=255;
    for Y:=3 to 37 do for X:=17 to 24 do G.Mask[Y*41+X]:=255;
    G.Strokes[0].Points[0]:=PointF(3,10); G.Strokes[0].Points[1]:=PointF(37,10);
    G.Strokes[1].Points[0]:=PointF(20.5,3); G.Strokes[1].Points[1]:=PointF(20.5,37);
    PrepareGlyphTiming(G); FirstEnd:=G.Strokes[0].Length;
    for Y:=9 to 11 do for X:=3 to 37 do
      Check(G.Reveal[Y*41+X]<=FirstEnd+1E-5,'Thin horizontal transfer has an intersection hole');
    for Y:=3 to 37 do if (Y<9) or (Y>11) then
      for X:=17 to 24 do Check(G.Reveal[Y*41+X]>FirstEnd,'Thick future vertical stroke leaked into thin horizontal transfer');
    // 縦横を入れ替えても同じ領域関係になること。
    FillChar(G.Mask[0],Length(G.Mask),0);
    for Y:=3 to 37 do for X:=9 to 11 do G.Mask[Y*41+X]:=255;
    for Y:=17 to 24 do for X:=3 to 37 do G.Mask[Y*41+X]:=255;
    G.Strokes[0].Points[0]:=PointF(10,3); G.Strokes[0].Points[1]:=PointF(10,37);
    G.Strokes[1].Points[0]:=PointF(3,20.5); G.Strokes[1].Points[1]:=PointF(37,20.5);
    PrepareGlyphTiming(G); FirstEnd:=G.Strokes[0].Length;
    for Y:=3 to 37 do for X:=9 to 11 do
      Check(G.Reveal[Y*41+X]<=FirstEnd+1E-5,'Thin vertical transfer has an intersection hole');
    for Y:=17 to 24 do for X:=3 to 37 do if (X<9) or (X>11) then
      Check(G.Reveal[Y*41+X]>FirstEnd,'Thick future horizontal stroke leaked into thin vertical transfer');
    Writeln('PASS stroke transfer fills intersections without future-arm dots and preserves mask and timing');
  finally G.Free end;
end;

procedure TestSelectedStrokeOperations;
var G: TWritingGlyph; State: TGlyphEditState; Indices: TArray<Integer>; I,Index: Integer;
begin
  G:=TWritingGlyph.Create;
  try
    G.Width:=32; G.Height:=32; SetLength(G.Mask,1024); FillChar(G.Mask[0],1024,255);
    SetLength(G.Strokes,6);
    for I:=0 to 5 do
    begin
      G.Strokes[I].ID:=70+I; SetLength(G.Strokes[I].Points,2);
      G.Strokes[I].Points[0]:=PointF(2,I*4+2); G.Strokes[I].Points[1]:=PointF(20,I*4+2);
    end;
    PrepareGlyphTiming(G); State:=CaptureGlyphState(G);
    Check(MoveSelectedStrokes(G,[1,3],5,Indices),'Move two nonadjacent rows to insertion slot');
    Check((Indices[0]=3) and (Indices[1]=4),'Moved row selection indices');
    Check((G.Strokes[0].ID=70) and (G.Strokes[1].ID=72) and (G.Strokes[2].ID=74) and
      (G.Strokes[3].ID=71) and (G.Strokes[4].ID=73) and (G.Strokes[5].ID=75),'Group insertion order');
    RestoreGlyphState(G,State);
    Check(not MoveSelectedStrokes(G,[1,2],2,Indices),'Drop into own selection must be a no-op');
    Check(not MoveSelectedStrokes(G,[1,1],3,Indices),'Duplicate row selection accepted');
    Check(ShiftSelectedStrokes(G,[1,2,4],-1,Indices),'Move selected rows up');
    Check((G.Strokes[0].ID=71) and (G.Strokes[1].ID=72) and (G.Strokes[3].ID=74),'Up movement order');
    Check(ShiftSelectedStrokes(G,Indices,1,Indices),'Move selected rows back down');
    for I:=0 to 5 do Check(G.Strokes[I].ID=70+I,'Up/down movement roundtrip');
    RestoreGlyphState(G,State);
    Check(JoinSelectedStrokes(G,[4,0,2],Index) and (Index=0),'Join nonadjacent multiple selection');
    Check((Length(G.Strokes)=4) and (G.Strokes[0].ID=70) and (G.Strokes[1].ID=71) and
      (G.Strokes[2].ID=73) and (G.Strokes[3].ID=75),'Join changed unrelated row order or IDs');
    Check(not JoinSelectedStrokes(G,[0],Index),'Single selection join should be disabled');
    Writeln('PASS multi-selection insertion, block movement, ordered join and unchanged IDs');
  finally G.Free end;
end;

procedure MakeBranchFixture(G: TWritingGlyph; BranchFirst: Boolean);
var Main,Branch,Other: TStroke;
begin
  Main:=Default(TStroke); Main.ID:=73; Main.PinnedVertices:=[1];
  Main.Points:=[PointF(14,7),PointF(14,16),PointF(13,26),PointF(12,36),PointF(12,45),
    PointF(15,50),PointF(19,50),PointF(24,46),PointF(28,40),PointF(30,34)];
  Branch:=Default(TStroke); Branch.ID:=41; Branch.PinnedVertices:=[3];
  Branch.Points:=[PointF(15,50),PointF(15,53),PointF(16,56),PointF(16,60)];
  Other:=Default(TStroke); Other.ID:=99; Other.Points:=[PointF(50,8),PointF(56,14)];
  if BranchFirst then G.Strokes:=[Branch,Other,Main] else G.Strokes:=[Main,Other,Branch];
  PrepareGlyphTiming(G);
end;

procedure CheckAbsorbedBranch(G: TWritingGlyph; const StartPoint,EndPoint: TPointF);
var I,Visits: Integer; TipPinned: Boolean;
begin
  Check((Length(G.Strokes)=2) and (G.Strokes[0].ID=73) and (G.Strokes[1].ID=99),
    'Branch absorption lost the main identity or changed an unselected stroke');
  Check((G.Strokes[0].Points[0]=StartPoint) and (G.Strokes[0].Points[High(G.Strokes[0].Points)]=EndPoint),
    'Branch absorption changed main direction or endpoints');
  Visits:=0; TipPinned:=False;
  for I:=0 to High(G.Strokes[0].Points) do
  begin
    if Distance(G.Strokes[0].Points[I],PointF(16,60))<0.01 then Inc(Visits);
    if I>0 then Check(Distance(G.Strokes[0].Points[I-1],G.Strokes[0].Points[I])<2.5,
      'Branch absorption left a jump or a sharp isolated point');
  end;
  for I in G.Strokes[0].PinnedVertices do
    if Distance(G.Strokes[0].Points[I],PointF(16,60))<0.01 then TipPinned:=True;
  Check((Visits=1) and TipPinned,'Main must pass the branch tip once and expose its editing vertex');
end;

procedure SaveBranchDiagram(G: TWritingGlyph; const FileName: string);
const Colors: array[0..4] of TColor=($4848D6,$CE8742,$74A153,$B667B1,$C2B13C);
var Bitmap: TBitmap; PNG: TPngImage; I,J,X,Y: Integer; Fit: Double; P,Q: TPointF;
  Row: PByte;
begin
  Fit:=4;
  Bitmap:=TBitmap.Create; PNG:=TPngImage.Create;
  try
    Bitmap.PixelFormat:=pf32bit; Bitmap.SetSize(Max(1,G.Width),Max(1,G.Height));
    for Y:=0 to G.Height-1 do
    begin
      Row:=Bitmap.ScanLine[Y];
      for X:=0 to G.Width-1 do
      begin
        I:=255-G.Mask[Y*G.Width+X] div 5;
        Row[X*4]:=I; Row[X*4+1]:=I; Row[X*4+2]:=I; Row[X*4+3]:=255;
      end;
    end;
    var CanvasImage: TBitmap; CanvasImage:=TBitmap.Create;
    try
      CanvasImage.SetSize(Round(G.Width*Fit)+40,Round(G.Height*Fit)+40);
      CanvasImage.Canvas.Brush.Color:=clWhite; CanvasImage.Canvas.FillRect(CanvasImage.Canvas.ClipRect);
      CanvasImage.Canvas.StretchDraw(Rect(20,20,20+Round(G.Width*Fit),20+Round(G.Height*Fit)),Bitmap);
      for I:=0 to High(G.Strokes) do
      begin
        CanvasImage.Canvas.Pen.Width:=3; CanvasImage.Canvas.Pen.Color:=Colors[I mod Length(Colors)];
        for J:=0 to High(G.Strokes[I].Points) do
        begin
          P:=G.Strokes[I].Points[J]; X:=20+Round(P.X*Fit); Y:=20+Round(P.Y*Fit);
          if J=0 then CanvasImage.Canvas.MoveTo(X,Y) else CanvasImage.Canvas.LineTo(X,Y);
        end;
        for J in EditingVertices(G.Strokes[I]) do
        begin
          P:=G.Strokes[I].Points[J]; X:=20+Round(P.X*Fit); Y:=20+Round(P.Y*Fit);
          CanvasImage.Canvas.Brush.Color:=clWhite; CanvasImage.Canvas.Ellipse(X-4,Y-4,X+5,Y+5);
        end;
        P:=G.Strokes[I].Points[0]; Q:=G.Strokes[I].Points[High(G.Strokes[I].Points)];
        CanvasImage.Canvas.Brush.Color:=Colors[I mod Length(Colors)];
        X:=20+Round(P.X*Fit); Y:=20+Round(P.Y*Fit); CanvasImage.Canvas.Ellipse(X-6,Y-6,X+7,Y+7);
        X:=20+Round(Q.X*Fit); Y:=20+Round(Q.Y*Fit); CanvasImage.Canvas.Rectangle(X-6,Y-6,X+7,Y+7);
      end;
      PNG.Assign(CanvasImage); PNG.SaveToFile(TPath.Combine(OutputDirectory,FileName));
    finally CanvasImage.Free end;
  finally PNG.Free; Bitmap.Free end;
end;

procedure TestBranchAbsorption;
var G,Loaded,Actual,Work: TWritingGlyph; Engine: TWritingFontEngine; S: TWritingSettings;
  State,After: TGlyphEditState; MainSide,BranchSide,Row,MainIndex,BranchIndex,I,Index: Integer;
  StartPoint,EndPoint: TPointF; Mask: TBytes; Attachment: TStrokeBranch;
  Folder,FileName,Warning: string; Reversed: Boolean;
begin
  G:=TWritingGlyph.Create; Loaded:=TWritingGlyph.Create; Folder:='';
  try
    G.Width:=80; G.Height:=72; SetLength(G.Mask,80*72); FillChar(G.Mask[0],Length(G.Mask),255); Mask:=Copy(G.Mask);
    for Row:=0 to 1 do for MainSide:=0 to 1 do for BranchSide:=0 to 1 do
    begin
      MakeBranchFixture(G,Row=1); MainIndex:=0; BranchIndex:=2;
      if Row=1 then begin MainIndex:=2; BranchIndex:=0 end;
      if MainSide=1 then ReverseGlyphStroke(G,MainIndex);
      if BranchSide=1 then ReverseGlyphStroke(G,BranchIndex);
      StartPoint:=G.Strokes[MainIndex].Points[0]; EndPoint:=G.Strokes[MainIndex].Points[High(G.Strokes[MainIndex].Points)];
      Reversed:=G.Strokes[MainIndex].Reversed; State:=CaptureGlyphState(G);
      Check(FindStrokeBranch(G.Strokes[MainIndex],G.Strokes[BranchIndex],Attachment),'Cannot detect endpoint-to-interior branch');
      Check(JoinSelectedStrokes(G,[2,0],Index) and (Index=0),'Join did not absorb an interior branch');
      CheckAbsorbedBranch(G,StartPoint,EndPoint);
      Check(G.Strokes[0].Reversed=Reversed,'Absorption changed the main reversed flag');
      Check(CompareMem(@Mask[0],@G.Mask[0],Length(Mask)),'Absorption modified the font mask');
      After:=CaptureGlyphState(G); RestoreGlyphState(G,State);
      Check((Length(G.Strokes)=3) and (Length(G.Strokes[MainIndex].Points)=10),'Undo did not restore branch geometry');
      RestoreGlyphState(G,After); CheckAbsorbedBranch(G,StartPoint,EndPoint);
    end;
    G.Character:='枝'; G.FontID:=THashSHA2.GetHashString('Branch absorption '+TGUID.NewGuid.ToString);
    Folder:=TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),G.FontID); FileName:=TPath.Combine(Folder,'679D.json');
    SaveGlyphLearning(G); Loaded.FontID:=G.FontID; Loaded.Character:=G.Character; Loaded.Width:=G.Width; Loaded.Height:=G.Height;
    Check(LoadGlyphLearning(Loaded,Warning) and (Warning=''),'Absorbed branch did not reload');
    CheckAbsorbedBranch(Loaded,StartPoint,EndPoint);
    MakeBranchFixture(G,True);
    var Main,Branch: TStroke; Main:=G.Strokes[2]; Branch:=Default(TStroke); Branch.ID:=42;
    Branch.Points:=[PointF(13,26),PointF(7,26)]; G.Strokes:=[G.Strokes[0],G.Strokes[1],Branch,Main];
    Check(JoinSelectedStrokes(G,[0,2,3],Index),'Cannot absorb multiple branches before joining row order');
    CheckAbsorbedBranch(G,PointF(14,7),PointF(30,34));
    var Found: Boolean; Found:=False;
    for I in G.Strokes[0].PinnedVertices do if Distance(G.Strokes[0].Points[I],PointF(7,26))<0.01 then Found:=True;
    Check(Found,'Second absorbed branch tip was lost');
    Main.Points:=[PointF(2,4),PointF(25,4)]; Main.PinnedVertices:=nil;
    Branch.Points:=[PointF(25,4),PointF(31,4)]; Branch.PinnedVertices:=nil;
    Check(not FindStrokeBranch(Main,Branch,Attachment),'Ordinary endpoint join was misclassified as a branch');
    Branch.Points:=[PointF(8,4),PointF(12,10),PointF(18,4)];
    Check(not FindStrokeBranch(Main,Branch,Attachment),'A double-attached loop was treated as a branch');
    Branch.Points:=[PointF(8,5),PointF(20,5)];
    Check(not FindStrokeBranch(Main,Branch,Attachment),'A nearby parallel path was treated as a branch');
    Writeln('PASS branch absorption in both directions and row orders, multiple branches, undo, learning and ordinary joins');
  finally
    Loaded.Free; G.Free;
    if (Folder<>'') and TFile.Exists(FileName) then TFile.Delete(FileName);
    if (Folder<>'') and TDirectory.Exists(Folder) then TDirectory.Delete(Folder,False);
  end;
  // 現在の「に」を読取専用で複製する。ユーザー学習は保存せず、診断画像だけ出す。
  Engine:=TWritingFontEngine.Create; Work:=TWritingGlyph.Create;
  try
    S:=DefaultWritingSettings; Engine.Configure(S); Actual:=Engine.Glyph('に');
    if Length(Actual.Strokes)>=2 then if FindStrokeBranch(Actual.Strokes[0],Actual.Strokes[1],Attachment) then
    begin
      Work.Width:=Actual.Width; Work.Height:=Actual.Height; Work.Mask:=Copy(Actual.Mask);
      State:=CaptureGlyphState(Actual); RestoreGlyphState(Work,State);
      SaveBranchDiagram(Work,'branch_before.png');
      Check(JoinSelectedStrokes(Work,[0,1],Index),'Actual に branch absorption failed');
      SaveBranchDiagram(Work,'branch_after.png');
      Check(Length(Work.Strokes)=Length(Actual.Strokes)-1,'Actual に branch was not removed');
    end;
  finally Work.Free; Engine.Free end;
end;

procedure TestFontCacheAndLayout;
var S: TWritingSettings; R: TWritingRenderer; G: TWritingGlyph;
  P: TArray<TPlacedGlyph>; ID: string; Duration: Double;
begin
  R:=TWritingRenderer.Create;
  try
    S:=DefaultWritingSettings; S.Text:='のの'; R.Prepare(S); P:=R.PlacedGlyphs;
    Check((Length(P)=2) and (P[0].Glyph=P[1].Glyph),'Repeated character does not share glyph data');
    G:=P[0].Glyph; ID:=R.Engine.FontID; Duration:=R.Duration(S);
    S.Scale:=250; S.X:=10; S.Speed:=420; R.Prepare(S);
    Check((R.PlacedGlyphs[0].Glyph=G) and (R.Engine.FontID=ID),'Frame parameters discarded glyph cache');
    Check(Abs(R.Duration(S)-Duration*240/420)<1E-6,'Duration does not scale with speed');
    S.FontSize:=120; R.Prepare(S); Check(R.PlacedGlyphs[0].Glyph=G,'Font size unnecessarily reanalyzed glyph');
    S.Bold:=True; R.Prepare(S); Check(R.Engine.FontID<>ID,'Font style learning identity collision');
    S.Bold:=False; S.FontName:='ＭＳ ゴシック'; R.Prepare(S); Check(R.Engine.FontID<>ID,'Font family learning identity collision');
    S.Text:='漢あア1A。'; R.Prepare(S); P:=R.PlacedGlyphs;
    Check(Length(P)=6,'Character category layout');
    Check(Abs(P[0].Scale-S.FontSize/AW_EM)<1E-6,'Kanji size ratio');
    Check(Abs(P[1].Scale-S.FontSize*0.9/AW_EM)<1E-6,'Hiragana size ratio');
    Check(Abs(P[2].Scale-S.FontSize*0.95/AW_EM)<1E-6,'Katakana size ratio');
    Check(Abs((P[0].Y+P[0].Glyph.OriginY*P[0].Scale)-(P[1].Y+P[1].Glyph.OriginY*P[1].Scale))<1E-6,'Mixed-size baseline alignment');
    Writeln('PASS shared glyph cache, font/style identity, category ratios and baseline');
  finally R.Free end;
end;

procedure TestFinalFont;
var S: TWritingSettings; DC: HDC; Font: HFONT; Old: HGDIOBJ;
  GM: TGlyphMetrics; Matrix: TMat2; Bytes: TBytes; Size: Cardinal; W,H,X,Y,I,Stride,Expected: Integer;
  Pixels: TWritingPixels;
begin
  S:=DefaultWritingSettings; S.Text:='永'; S.FontName:='ＭＳ ゴシック'; S.FontSize:=128;
  S.ShowPen:=False; S.Ratios[ckKanji]:=1; Configure(S);
  DC:=CreateCompatibleDC(0); Font:=CreateFont(-128,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,
    OUT_TT_ONLY_PRECIS,CLIP_DEFAULT_PRECIS,ANTIALIASED_QUALITY,DEFAULT_PITCH,PChar(S.FontName));
  Old:=SelectObject(DC,Font);
  try
    FillChar(Matrix,SizeOf(Matrix),0); Matrix.eM11.Value:=1; Matrix.eM22.Value:=1;
    Size:=GetGlyphOutlineW(DC,Ord('永'),GGO_GRAY8_BITMAP,GM,0,nil,Matrix);
    Check(Size<>GDI_ERROR,'Independent glyph extraction'); SetLength(Bytes,Size);
    GetGlyphOutlineW(DC,Ord('永'),GGO_GRAY8_BITMAP,GM,Size,@Bytes[0],Matrix);
    W:=GM.gmBlackBoxX; H:=GM.gmBlackBoxY; Stride:=(W+3) and not 3;
    SizeFrame(W+100,H+100); Pixels:=Render(10000);
    for Y:=0 to H-1 do for X:=0 to W-1 do
    begin
      Expected:=Min(255,(Integer(Bytes[Y*Stride+X])*255+32) div 64);
      I:=(Y+50)*Scene.Width+X+50;
      Check(Pixels[I].A=Expected,'Final glyph differs from Windows font mask');
    end;
    SavePNG(Pixels,Scene.Width,Scene.Height,'font_original.png');
  finally SelectObject(DC,Old); DeleteObject(Font); DeleteDC(DC) end;
  Writeln('PASS final glyph equals original font mask, pixel for pixel');
end;

procedure TestProduction;
var S: TWritingSettings; A,B,Final,Previous: TWritingPixels; Duration,D2: Double;
  I,J,Count: Integer; Watch: TStopwatch;
begin
  S:=DefaultWritingSettings; S.FontName:='游明朝'; S.Text:='拝啓'+sLineBreak+'お元気ですか。'+sLineBreak+'またお会いしましょう。';
  S.FontSize:=48; S.ShowPen:=False; SizeFrame(960,540); Configure(S);
  Watch:=TStopwatch.StartNew; Duration:=Renderer.Duration(S); Watch.Stop;
  Writeln(Format('First preparation %.3f ms; duration %.6f sec',[Watch.Elapsed.TotalMilliseconds,Duration]));
  Check(Duration>0,'No writing timeline'); A:=Render(0); Check(Coverage(A)=0,'Ink visible at t=0');
  Final:=Render(Duration+10); Check(Coverage(Final)>4000,'Final text missing');
  Previous:=A;
  for I:=1 to 12 do
  begin
    A:=Render(Duration*I/12); Count:=0;
    for J:=0 to High(A) do if A[J].A<Previous[J].A then Inc(Count);
    Check(Count=0,'Ink disappeared while writing'); Previous:=A;
    if (I mod 3)=0 then SavePNG(A,Scene.Width,Scene.Height,Format('writing_%2.2d.png',[I]));
  end;
  Check(Same(Previous,Final),'Text incomplete at calculated finish time');
  A:=Render(Duration*0.37); Render(Duration*0.82); B:=Render(Duration*0.37);
  Check(Same(A,B),'Backward seek differs');
  B:=Render(Duration+1000); Check(Same(B,Final),'Completed writing does not persist');
  S.Speed:=S.Speed*2; Configure(S); B:=Render(Duration*0.37/2); Check(Same(A,B),'Speed/time equivalence');
  S.Scale:=200; D2:=Renderer.Duration(S); Check(Abs(D2-Duration/2)<1E-6,'Scale altered writing duration');
  S.Speed:=240; S.Scale:=100; S.ShowPen:=True;
  for I:=0 to 3 do
  begin S.Pen:=TPenKind(I); Configure(S); A:=Render(Duration*0.2); SavePNG(A,Scene.Width,Scene.Height,'pen_'+IntToStr(I)+'.png') end;
  A:=Render(Duration*0.2); Render(Duration*0.4); B:=Render(Duration*0.2); Check(Same(A,B),'Pen seek differs');
  S.ShowPen:=False; S.Transparency:=100; Configure(S); Check(Coverage(Render(Duration+1))=0,'Transparency 100 is not invisible');
  S.Transparency:=50; Configure(S); A:=Render(Duration+1);
  for I:=0 to High(A) do Check(A[I].A<=128,'Transparency not applied to ink');
  S.Transparency:=0; S.X:=30; S.Y:=-20; Configure(S); A:=Render(Duration+1);
  for I:=20 to Scene.Height-1 do for J:=0 to Scene.Width-31 do
    Check(A[(I-20)*Scene.Width+J+30].A=Final[I*Scene.Width+J].A,'X/Y transform is incorrect');
  S.X:=0; S.Y:=0; S.Vertical:=True; S.Text:='自動筆記'+sLineBreak+'こんにちは。'; S.FontSize:=56;
  Configure(S); D2:=Renderer.Duration(S); A:=Render(D2+1); SavePNG(A,Scene.Width,Scene.Height,'vertical.png');
  Check(Coverage(A)>1500,'Vertical text missing');
  S.Vertical:=False; S.Text:=''; Configure(S); A:=Render(10); Check(Coverage(A)=0,'Empty text is not transparent');
  SetLength(HostInput,Scene.Width*Scene.Height);
  for I:=0 to High(HostInput) do begin HostInput[I].R:=35; HostInput[I].G:=70; HostInput[I].B:=100; HostInput[I].A:=180 end;
  Check(Same(Render(0),HostInput),'Empty text modified input');
  S.Text:='入力画像に重ねる'; Configure(S); A:=Render(1000); Check(not Same(A,HostInput),'Text not composited over input');
  SavePNG(A,Scene.Width,Scene.Height,'composite.png'); HostInput:=nil;
  S.Text:='A1 あア永。'; Configure(S); A:=Render(1000); Check(Coverage(A)>1000,'Character categories missing');
  Obj.Width:=0; Obj.Height:=0; Check(Table^.Func_Proc_Video(@Video)=1,'Scene-size fallback failed');
  Obj.Width:=960; Obj.Height:=540;
  Check(Table^.Func_Proc_Video(nil)=0,'Nil video not rejected');
  Video.UserData:=nil; Check(Table^.Func_Proc_Video(@Video)=0,'Nil session not rejected');
  Writeln('PASS production animation, reverse seek, speed/scale, pens, vertical, composition, invalid inputs');
end;

function UIGet(Handle: OBJECT_HANDLE; Effect,Item: PWideChar): PAnsiChar; cdecl;
begin
  Result:=nil;
  if string(Item)='詳細設定' then Result:=PAnsiChar(UIValues[0]);
  if string(Item)='表示文字列' then Result:=PAnsiChar(UIValues[1]);
  if string(Item)='ペン種類' then Result:=PAnsiChar(UIValues[2]);
  if string(Item)='ペン速度' then Result:=PAnsiChar(UIValues[3]);
  if string(Item)='ペン角度' then Result:=PAnsiChar(UIValues[4]);
  if string(Item)='光源X' then Result:=PAnsiChar(UIValues[5]);
  if string(Item)='光源Y' then Result:=PAnsiChar(UIValues[6]);
  if string(Item)='ペンサイズ' then Result:=PAnsiChar(UIValues[7]);
end;

function UISet(Handle: OBJECT_HANDLE; Effect,Item: PWideChar; Value: PAnsiChar): Boolean; cdecl;
begin
  Result:=False;
  if (Handle<>Pointer(1234)) or (string(Effect)<>'自動筆記:2') then begin UIError:='Wrong settings target'; Exit end;
  if string(Item)='詳細設定' then begin UIValues[0]:=UTF8String(Value); DetailBacking:=string(UIValues[0]); DetailsItem^.Value:=PChar(DetailBacking); Result:=True end;
  if string(Item)='表示文字列' then begin UIValues[1]:=UTF8String(Value); TextBacking:=string(UIValues[1]); TextItem^.Value:=PChar(TextBacking); Result:=True end;
  if string(Item)='ペン種類' then begin UIValues[2]:=UTF8String(Value); Result:=True end;
  if string(Item)='ペン速度' then begin UIValues[3]:=UTF8String(Value); Result:=True end;
  if string(Item)='ペン角度' then begin UIValues[4]:=UTF8String(Value); Result:=True end;
  if string(Item)='光源X' then begin UIValues[5]:=UTF8String(Value); Result:=True end;
  if string(Item)='光源Y' then begin UIValues[6]:=UTF8String(Value); Result:=True end;
  if string(Item)='ペンサイズ' then begin UIValues[7]:=UTF8String(Value); Result:=True end;
  if Result then Inc(UIEdits);
end;

function FindUIWindow(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var Name: array[0..127] of Char;
begin
  GetClassName(Wnd,Name,Length(Name));
  if string(Name)='TWritingSettingsForm' then DialogHandle:=Wnd;
  Result:=True;
end;

function FindUIChild(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var Name,Text: array[0..255] of Char;
begin
  GetClassName(Wnd,Name,Length(Name)); GetWindowText(Wnd,Text,Length(Text));
  if string(Name)='TMemo' then MemoHandle:=Wnd;
  if string(Name)='TPageControl' then PageHandle:=Wnd;
  if (string(Name)='TComboBox') and (SendMessage(Wnd,CB_GETCOUNT,0,0)=6) then PenHandle:=Wnd;
  if (string(Name)='TSpinEdit') and (string(Text)='35') then AngleHandle:=Wnd;
  if (string(Name)='TSpinEdit') and (string(Text)='-100') then LightXHandle:=Wnd;
  if (string(Name)='TSpinEdit') and (string(Text)='-140') then LightYHandle:=Wnd;
  if string(Name)='TNumberBox' then PenSizeHandle:=Wnd;
  if (string(Name)='TButton') and ((string(Text)='適用して閉じる') or (string(Text)='キャンセル') or
    (string(Text)='元に戻す') or (string(Text)='やり直す')) then ApplyHandle:=Wnd;
  if ((string(Name)='TListBox') or (string(Name)='TWritingStrokeListBox')) and
    (GetWindowLong(Wnd,GWL_STYLE) and LBS_OWNERDRAWFIXED<>0) then
  begin
    if GetParent(Wnd)<>0 then
    begin
      // 右ペインのリストは文字一覧より広い。HWNDはこの専用テストフォームのものだけ。
      var R: TRect; GetClientRect(Wnd,R); if R.Width>180 then EditingStrokeList:=Wnd;
    end;
  end;
  if string(Name)='TWritingPaintBox' then
    if IsWindowVisible(Wnd) then
      if UIStage<2 then PreviewSurface:=Wnd else EditorSurface:=Wnd;
  Result:=True;
end;

procedure CaptureWindow(Wnd: HWND; const FileName: string);
var B: TBitmap; R: TRect; Pixels: TWritingPixels; X,Y: Integer; Row: PByte;
begin
  GetWindowRect(Wnd,R); B:=TBitmap.Create;
  try
    B.PixelFormat:=pf32bit; B.SetSize(R.Width,R.Height);
    if not PrintWindow(Wnd,B.Canvas.Handle,0) then raise Exception.Create('PrintWindow failed');
    SetLength(Pixels,R.Width*R.Height);
    for Y:=0 to R.Height-1 do
    begin
      Row:=B.Scanline[Y];
      for X:=0 to R.Width-1 do
      begin
        Pixels[Y*R.Width+X].B:=Row[X*4]; Pixels[Y*R.Width+X].G:=Row[X*4+1];
        Pixels[Y*R.Width+X].R:=Row[X*4+2]; Pixels[Y*R.Width+X].A:=255;
      end;
    end;
    SavePNG(Pixels,R.Width,R.Height,FileName);
  finally B.Free end;
end;

procedure CaptureDialog(const FileName: string);
begin CaptureWindow(DialogHandle,FileName) end;

procedure CtrlKey(Key: Word);
var Before,Keys: TKeyboardState;
begin
  GetKeyboardState(Before); Keys:=Before; Keys[VK_CONTROL]:=$80;
  try SetKeyboardState(Keys); SendMessage(DialogHandle,WM_KEYDOWN,Key,0)
  finally SetKeyboardState(Before) end;
end;

function FindPopup(Wnd: HWND; Param: LPARAM): BOOL; stdcall;
var Name: array[0..63] of Char;
begin
  GetClassName(Wnd,Name,Length(Name));
  if (string(Name)='#32768') and IsWindowVisible(Wnd) then PopupWindow:=Wnd;
  Result:=True;
end;

function OpenPopupHandle: HMENU;
var Info: TMenuBarInfo;
begin
  PopupWindow:=0; EnumThreadWindows(GetCurrentThreadId,@FindPopup,0);
  Check(PopupWindow<>0,'Expected a native popup menu');
  FillChar(Info,SizeOf(Info),0); Info.cbSize:=SizeOf(Info);
  Check(GetMenuBarInfo(PopupWindow,-4,0,Info),'Cannot inspect native popup'); Result:=Info.hMenu;
end;

procedure ChoosePopupItem(Index: Integer);
var Menu: HMENU; Command: UINT; Owner: HWND; Info: TGUIThreadInfo;
begin
  Menu:=OpenPopupHandle; Command:=GetMenuItemID(Menu,Index);
  Check(Command<>High(UINT),'Popup item has no command');
  Check((GetMenuState(Menu,Index,MF_BYPOSITION) and (MF_DISABLED or MF_GRAYED))=0,'Popup command disabled');
  FillChar(Info,SizeOf(Info),0); Info.cbSize:=SizeOf(Info); GetGUIThreadInfo(GetCurrentThreadId,Info);
  Owner:=Info.hwndMenuOwner; if Owner=0 then Owner:=GetWindow(PopupWindow,GW_OWNER);
  Check(Owner<>0,'Popup menu owner missing');
  EndMenu; PostMessage(Owner,WM_COMMAND,Command,0);
end;

procedure PostContext(Surface: HWND; const Position: TPoint);
var P: TPoint;
begin
  P:=Position; ClientToScreen(Surface,P);
  PostMessage(Surface,WM_CONTEXTMENU,WPARAM(Surface),(P.X and $FFFF) or ((P.Y and $FFFF) shl 16));
end;

procedure CheckRetainedFrame(Surface: HWND; const Description: string);
var DC: HDC; Before: COLORREF; I: Integer;
begin
  Check(Surface<>0,Description+': missing independent paint surface');
  RedrawWindow(Surface,nil,0,RDW_INVALIDATE or RDW_UPDATENOW);
  DC:=GetDC(Surface);
  try
    Before:=GetPixel(DC,8,8);
    Check(Before=RGB(240,240,240),Description+': animation checkerboard is missing');
    // 背景消去と次のWM_PAINTの間にも、表示済みフレームが消えないことを検査する。
    for I:=1 to 20 do
    begin
      Check(SendMessage(Surface,WM_ERASEBKGND,WPARAM(DC),0)=1,Description+': erase was not handled');
      Check(GetPixel(DC,8,8)=Before,Description+': frame blanked before the next paint');
    end;
  finally ReleaseDC(Surface,DC) end;
end;

procedure UITick(Wnd: HWND; Msg: UINT; Event: UINT_PTR; Time: DWORD); stdcall;
var Header: TNMHdr;
begin
  Inc(UICount);
  try
    if DialogHandle=0 then EnumThreadWindows(GetCurrentThreadId,@FindUIWindow,0);
    if UICount>50 then raise Exception.Create('Settings UI timed out');
    if DialogHandle=0 then Exit;
    case UIStage of
      0: begin
        EnumChildWindows(DialogHandle,@FindUIChild,0);
        if (MemoHandle=0) or (PageHandle=0) or (PenHandle=0) then raise Exception.Create('Settings UI control missing');
        Check(ApplyHandle=0,'Apply/cancel buttons must be removed');
        CheckRetainedFrame(PreviewSurface,'Text preview');
        CaptureDialog('ui_preview.png');
        SendMessage(MemoHandle,WM_SETTEXT,0,LPARAM(PChar('自'+sLineBreak+'本文の更新')));
        Check(SendMessage(PenHandle,CB_GETCURSEL,0,0)=2,'Opening settings changed the saved fountain pen');
        SendMessage(PenHandle,CB_SETCURSEL,DialogPenChoice,0);
        SendMessage(GetParent(PenHandle),WM_COMMAND,(GetDlgCtrlID(PenHandle) and $FFFF) or (CBN_SELCHANGE shl 16),LPARAM(PenHandle));
        Check(AngleHandle<>0,'Missing pen-angle control');
        if ChangeAngleInDialog then
        begin
          SendMessage(AngleHandle,WM_SETTEXT,0,LPARAM(PChar('-20')));
          SendMessage(GetParent(AngleHandle),WM_COMMAND,
            (GetDlgCtrlID(AngleHandle) and $FFFF) or (EN_CHANGE shl 16),LPARAM(AngleHandle));
          Check((LightXHandle<>0) and (LightYHandle<>0),'Missing light XY controls');
          SendMessage(LightXHandle,WM_SETTEXT,0,LPARAM(PChar('180')));
          SendMessage(GetParent(LightXHandle),WM_COMMAND,(GetDlgCtrlID(LightXHandle) and $FFFF) or (EN_CHANGE shl 16),LPARAM(LightXHandle));
          SendMessage(LightYHandle,WM_SETTEXT,0,LPARAM(PChar('160')));
          SendMessage(GetParent(LightYHandle),WM_COMMAND,(GetDlgCtrlID(LightYHandle) and $FFFF) or (EN_CHANGE shl 16),LPARAM(LightYHandle));
          Check(PenSizeHandle<>0,'Missing fractional pen size control');
          SendMessage(PenSizeHandle,WM_SETTEXT,0,LPARAM(PChar('150.25')));
          SendMessage(GetParent(PenSizeHandle),WM_COMMAND,(GetDlgCtrlID(PenSizeHandle) and $FFFF) or (EN_CHANGE shl 16),LPARAM(PenSizeHandle));
          SendMessage(PenSizeHandle,WM_KEYDOWN,VK_UP,0);
        end;
        UIStage:=1;
      end;
      1: begin UIStage:=2 end;
      2: begin
        SendMessage(PageHandle,TCM_SETCURSEL,1,0);
        FillChar(Header,SizeOf(Header),0); Header.hwndFrom:=PageHandle; Header.idFrom:=0;
        Header.code:=TCN_SELCHANGE;
        SendMessage(GetParent(PageHandle),WM_NOTIFY,Header.idFrom,LPARAM(@Header)); UIStage:=3;
      end;
      3: begin
        EnumChildWindows(DialogHandle,@FindUIChild,0);
        Check(EditorSurface<>0,'Missing stroke editor paint surface');
        Check(ApplyHandle=0,'Editor button panel must be removed');
        Check(GetWindowLong(EditingStrokeList,GWL_STYLE) and LBS_EXTENDEDSEL<>0,'Stroke list must support multiple selection');
        CaptureDialog('ui_stroke_editor.png');
        if SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)>1 then
        begin
          SetFocus(EditingStrokeList); SendMessage(EditingStrokeList,LB_SETSEL,0,-1);
          SendMessage(EditingStrokeList,LB_SETSEL,1,1); SendMessage(EditingStrokeList,LB_SETCARETINDEX,1,0);
          SendMessage(GetParent(EditingStrokeList),WM_COMMAND,
            (GetDlgCtrlID(EditingStrokeList) and $FFFF) or (LBN_SELCHANGE shl 16),LPARAM(EditingStrokeList));
          CaptureDialog('ui_selected_stroke2.png');
        end;
        SetFocus(EditorSurface);
        SendMessage(DialogHandle,WM_KEYDOWN,VK_SPACE,0); UIStage:=4;
      end;
      4: begin
        CheckRetainedFrame(EditorSurface,'Single-character preview');
        CaptureDialog('ui_single_character.png'); KillTimer(0,UITimer); UITimer:=0;
        UIStage:=5; PostMessage(DialogHandle,WM_CLOSE,0,0);
      end;
    end;
  except
    on E: Exception do
    begin
      UIError:='stage '+IntToStr(UIStage)+': '+E.Message; KillTimer(0,UITimer); UITimer:=0;
      if DialogHandle<>0 then PostMessage(DialogHandle,WM_CLOSE,0,0);
    end;
  end;
end;

procedure TestSettingsDialog;
var S,R: TWritingSettings; Edit: TEDIT_SECTION; Mode: Integer;
begin
  for Mode:=0 to 3 do
  begin
  DialogHandle:=0; MemoHandle:=0; PageHandle:=0; PenHandle:=0; AngleHandle:=0;
  LightXHandle:=0; LightYHandle:=0; PenSizeHandle:=0;
  ApplyHandle:=0; PreviewSurface:=0; EditorSurface:=0; UIStage:=0; UICount:=0; UIEdits:=0; UIError:='';
  ChangeAngleInDialog:=Mode=1;
  DialogPenChoice:=1; if Mode=2 then DialogPenChoice:=5 else if Mode=3 then DialogPenChoice:=4;
  S:=DefaultWritingSettings; S.Speed:=240.25; S.PenAngle:=35.25; Configure(S);
  S.LightX:=-100.25; S.LightY:=-140.25; S.PenSize:=1.00005; Configure(S);
  UIValues[0]:=UTF8String(DetailBacking); UIValues[1]:=UTF8String(TextBacking);
  UIValues[2]:='万年筆'; UIValues[3]:='240.25,480,1'; UIValues[4]:='35.25,70,1'; FillChar(Edit,SizeOf(Edit),0);
  UIValues[5]:='-100.25,180,1'; UIValues[6]:='-140.25,160,1'; UIValues[7]:='100.005,200,1';
  Edit.GetObjectItemValue:=UIGet; Edit.SetObjectItemValue:=UISet;
  UITimer:=SetTimer(0,0,250,@UITick);
  Check(UITimer<>0,'Cannot start UI test timer');
  try Button^.Callback2(@Edit,Pointer(1234),'自動筆記:2','設定')
  finally if UITimer<>0 then KillTimer(0,UITimer) end;
  Check(UIError='','Settings UI failure: '+UIError); Check(UIStage=5,'Settings UI did not finish');
  Check(UIEdits=2+Ord(Mode=1)*5,Format('Only changed host items should be saved (mode %d, writes %d)',[Mode,UIEdits]));
  Check(DecodeHostText(string(UIValues[1]))='自'+sLineBreak+'本文の更新','UI text not sent to host');
  Check(string(UIValues[2])=string(AW_PEN_NAMES[AW_PEN_ORDER[DialogPenChoice]]),'UI pen not sent to host');
  Check(string(UIValues[3])='240.25,480,1','Unedited animated fractional speed was overwritten');
  if Mode<>1 then begin
    Check(string(UIValues[4])='35.25,70,1','Unedited animated fractional angle was overwritten');
    Check((string(UIValues[5])='-100.25,180,1') and (string(UIValues[6])='-140.25,160,1'),'Unedited light animation was overwritten');
    Check(string(UIValues[7])='100.005,200,1','Unedited fractional pen size animation was overwritten');
  end
  else begin
    Check(string(UIValues[4])='-20','UI angle not sent to host');
    R:=DefaultWritingSettings; ReadSettingsJSON(string(UIValues[0]),R);
    Check(R.PenAngle=-20,'Changed angle missing from detailed settings');
    Check((string(UIValues[5])='180') and (string(UIValues[6])='160') and (R.LightX=180) and (R.LightY=160),'Light XY not sent to host and details');
    Check((Abs(R.PenSize-1.5026)<1E-10) and (string(UIValues[7])='150.26'),'Pen size 0.01 step not sent to host and details');
  end;
  end;
  ChangeAngleInDialog:=False;
  Writeln('PASS close-to-apply settings, removed buttons, multiline text and pen synchronization');
  Writeln('PASS text and single-character preview retain their frame during background erase');
end;

procedure EditingClick(const Point: TPoint);
var Position: LPARAM;
begin
  Position:=(Point.X and $FFFF) or ((Point.Y and $FFFF) shl 16);
  SendMessage(EditorSurface,WM_MOUSEMOVE,0,Position);
  SendMessage(EditorSurface,WM_LBUTTONDOWN,MK_LBUTTON,Position);
  SendMessage(EditorSurface,WM_LBUTTONUP,0,Position);
end;

procedure NotifyStrokeSelection;
begin
  SendMessage(GetParent(EditingStrokeList),WM_COMMAND,
    (GetDlgCtrlID(EditingStrokeList) and $FFFF) or (LBN_SELCHANGE shl 16),LPARAM(EditingStrokeList));
end;

procedure SetNativeStrokeSelection(const Indices: TArray<Integer>);
var I: Integer;
begin
  SendMessage(EditingStrokeList,LB_SETSEL,0,-1);
  for I in Indices do SendMessage(EditingStrokeList,LB_SETSEL,1,I);
  if Length(Indices)>0 then SendMessage(EditingStrokeList,LB_SETCARETINDEX,Indices[0],0);
  NotifyStrokeSelection;
end;

procedure CheckSelectionHighlight;
var ListDC,EditorDC: HDC; Row: TRect; Color: COLORREF; Shift,Offset,X,Y,Count,Maximum: Integer;
begin
  RedrawWindow(EditorSurface,nil,0,RDW_INVALIDATE or RDW_UPDATENOW);
  RedrawWindow(EditingStrokeList,nil,0,RDW_INVALIDATE or RDW_UPDATENOW);
  SendMessage(EditingStrokeList,LB_GETITEMRECT,EditingSelectedStroke,LPARAM(@Row));
  ListDC:=GetDC(EditingStrokeList); EditorDC:=GetDC(EditorSurface);
  try
    Color:=GetPixel(ListDC,18,Row.Top+24); Maximum:=0;
    // 一覧の選択色と同色の太線が中央に十分な幅で描かれているかを確認する。
    for Shift:=-3 to 3 do
    begin
      Count:=0;
      for Offset:=-4 to 4 do
      begin
        X:=Round(EditingPoint.X-EditingNormal.Y*Shift*4+EditingNormal.X*Offset);
        Y:=Round(EditingPoint.Y+EditingNormal.X*Shift*4+EditingNormal.Y*Offset);
        if GetPixel(EditorDC,X,Y)=Color then Inc(Count);
      end;
      Maximum:=Max(Maximum,Count);
    end;
    Check(Maximum>=6,'Selected stroke highlight is too thin or differs from the row color');
  finally ReleaseDC(EditorSurface,EditorDC); ReleaseDC(EditingStrokeList,ListDC) end;
end;

procedure CheckPointDirectionReversed;
var Glyph: TWritingGlyph; Warning: string;
begin
  Glyph:=TWritingGlyph.Create;
  try
    Glyph.FontID:=EditingFontID; Glyph.Character:=EditingCharacter;
    Glyph.Width:=EditingGlyphWidth; Glyph.Height:=EditingGlyphHeight;
    Check(LoadGlyphLearning(Glyph,Warning) and (Warning=''),
      'Point direction reversal was not saved: '+Warning+'; file='+BoolToStr(TFile.Exists(EditingFile),True));
    Check(Glyph.Strokes[EditingSelectedStroke].Points[0]=EditingLast,'Point menu did not reverse the start');
    Check(Glyph.Strokes[EditingSelectedStroke].Points[High(Glyph.Strokes[EditingSelectedStroke].Points)]=EditingFirst,
      'Point menu did not reverse the end');
  finally Glyph.Free end;
end;

procedure StartNativeGroupDrag;
var R,Row: TRect; P: TPoint; Position: LPARAM; DC: HDC;
begin
  // マウスポインターは動かさず、検査フォームだけを一時的に最前面へ出して対象判定する。
  SetWindowPos(DialogHandle,HWND_TOPMOST,0,0,0,0,SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
  SetFocus(EditingStrokeList); SetNativeStrokeSelection([0,1]);
  SendMessage(EditingStrokeList,LB_GETITEMRECT,0,LPARAM(@Row));
  Position:=(60 and $FFFF) or (((Row.Top+Row.Bottom) div 2) shl 16);
  SendMessage(EditingStrokeList,WM_LBUTTONDOWN,MK_LBUTTON,Position);
  EditingDragCapture:=GetCapture; Check(EditingDragCapture<>0,'Automatic drag did not capture the mouse');
  GetClientRect(EditingStrokeList,R);
  SendMessage(EditingStrokeList,LB_GETITEMRECT,SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)-1,LPARAM(@Row));
  P:=Point(R.Width div 2,Row.Bottom-3); ClientToScreen(EditingStrokeList,P);
  ScreenToClient(EditingDragCapture,P);
  EditingDragPosition:=(P.X and $FFFF) or ((P.Y and $FFFF) shl 16);
  SendMessage(EditingDragCapture,WM_MOUSEMOVE,MK_LBUTTON,EditingDragPosition);
  SendMessage(EditingDragCapture,WM_MOUSEMOVE,MK_LBUTTON,EditingDragPosition+1);
  SendMessage(EditingDragCapture,WM_MOUSEMOVE,MK_LBUTTON,EditingDragPosition);
  RedrawWindow(EditingStrokeList,nil,0,RDW_INVALIDATE or RDW_UPDATENOW);
  DC:=GetDC(EditingStrokeList);
  try
    Check(GetPixel(DC,20,Row.Bottom-2)=$D06518,'Drag insertion line is not visible')
  finally ReleaseDC(EditingStrokeList,DC) end;
end;

procedure EditingTick(Wnd: HWND; Msg: UINT; Event: UINT_PTR; Time: DWORD); stdcall;
var Header: TNMHdr; R: TRect; Scale,X,Y: Double; Menu: HMENU; Position: LPARAM;
begin
  Inc(EditingTicks);
  try
    if DialogHandle=0 then EnumThreadWindows(GetCurrentThreadId,@FindUIWindow,0);
    if EditingTicks>50 then raise Exception.Create('Native editing test timed out');
    if DialogHandle=0 then Exit;
    case EditingStage of
      0: begin
        UIStage:=0; EnumChildWindows(DialogHandle,@FindUIChild,0);
        SendMessage(PageHandle,TCM_SETCURSEL,1,0);
        FillChar(Header,SizeOf(Header),0); Header.hwndFrom:=PageHandle; Header.code:=TCN_SELCHANGE;
        SendMessage(GetParent(PageHandle),WM_NOTIFY,0,LPARAM(@Header)); EditingStage:=1;
      end;
      1: begin
        UIStage:=3; EnumChildWindows(DialogHandle,@FindUIChild,0);
        Check((EditorSurface<>0) and (EditingStrokeList<>0),'Native edit controls missing');
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=EditingInitialCount,'Unexpected initial stroke list');
        GetClientRect(EditorSurface,R);
        Scale:=Min((R.Width-100)/Max(1,EditingGlyphWidth),(R.Height-100)/Max(1,EditingGlyphHeight));
        X:=(R.Width-EditingGlyphWidth*Scale)/2; Y:=(R.Height-EditingGlyphHeight*Scale)/2;
        EditingPoint:=Point(Round(X+EditingGlyphPoint.X*Scale),Round(Y+EditingGlyphPoint.Y*Scale));
        EditingSecondPoint:=Point(Round(X+EditingGlyphSecondPoint.X*Scale),Round(Y+EditingGlyphSecondPoint.Y*Scale));
        SetNativeStrokeSelection([EditingSelectedStroke]);
        CheckSelectionHighlight;
        CaptureDialog('ui_edit_before.png'); EditingStage:=2;
      end;
      2: begin
        Check(not TFile.Exists(EditingFile),'Selecting a point saved learning');
        CaptureDialog('ui_point_selected.png'); EditingStage:=3; PostContext(EditorSurface,EditingPoint);
      end;
      3: begin
        Menu:=OpenPopupHandle;
        Check(GetMenuItemCount(Menu)>=8,'Editor popup missing actions');
        Check(GetMenuState(Menu,2,MF_BYPOSITION) and (MF_GRAYED or MF_DISABLED)=0,'Line right-click must offer vertex creation');
        CaptureWindow(PopupWindow,'ui_point_menu.png'); EditingStage:=32; ChoosePopupItem(2);
      end;
      32: begin
        var Learned: TWritingGlyph; var Warning: string;
        Learned:=TWritingGlyph.Create;
        try
          Learned.FontID:=EditingFontID; Learned.Character:=EditingCharacter;
          Learned.Width:=EditingGlyphWidth; Learned.Height:=EditingGlyphHeight;
          Check(LoadGlyphLearning(Learned,Warning) and (Warning=''),'Native line vertex was not saved');
          Check(Length(Learned.Strokes[EditingSelectedStroke].PinnedVertices)=1,'Native line action did not create a pinned vertex');
        finally Learned.Free end;
        CaptureDialog('ui_vertex_created.png');
        EditingClick(EditingPoint);
        Position:=((EditingPoint.X+18) and $FFFF) or (((EditingPoint.Y+14) and $FFFF) shl 16);
        // 頂点作成後は同じ操作点をドラッグでき、2回のUndoで元の未学習状態へ戻る。
        SendMessage(EditorSurface,WM_LBUTTONDOWN,MK_LBUTTON,
          (EditingPoint.X and $FFFF) or ((EditingPoint.Y and $FFFF) shl 16));
        SendMessage(EditorSurface,WM_MOUSEMOVE,MK_LBUTTON,Position);
        SendMessage(EditorSurface,WM_LBUTTONUP,0,Position);
        CaptureDialog('ui_vertex_dragged.png'); SetFocus(EditorSurface); CtrlKey(Ord('Z'));
        Check(TFile.Exists(EditingFile),'Undo vertex drag removed the created vertex');
        CtrlKey(Ord('Z')); Check(not TFile.Exists(EditingFile),'Undo creation left vertex learning behind');
        EditingStage:=33; PostContext(EditorSurface,EditingPoint);
      end;
      33: begin
        OpenPopupHandle; EditingStage:=30; ChoosePopupItem(1);
      end;
      30: begin
        CheckPointDirectionReversed; CaptureDialog('ui_direction_reversed.png');
        SetFocus(EditorSurface); CtrlKey(Ord('Z'));
        Check(not TFile.Exists(EditingFile),'Undo point direction reversal left learning behind');
        EditingClick(EditingPoint); EditingStage:=31; PostContext(EditorSurface,EditingPoint);
      end;
      31: begin
        OpenPopupHandle; EditingStage:=4; ChoosePopupItem(0);
      end;
      4: begin
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=EditingInitialCount+1,'Native split click did not create a stroke');
        Check(TFile.Exists(EditingFile),'Native split did not persist learning');
        CaptureDialog('ui_edit_split.png'); EditingStage:=5;
        Position:=(EditingPoint.X and $FFFF) or ((EditingPoint.Y and $FFFF) shl 16);
        PostMessage(EditorSurface,WM_LBUTTONDOWN,MK_LBUTTON,Position); PostMessage(EditorSurface,WM_LBUTTONUP,0,Position);
      end;
      5: begin
        Menu:=OpenPopupHandle; Check(GetMenuItemCount(Menu)>=2,'Overlapping points must offer multiple colored choices');
        CaptureWindow(PopupWindow,'ui_overlap_choices.png'); EditingStage:=6; ChoosePopupItem(0);
      end;
      6: begin
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=EditingInitialCount+1,'Choosing a point changed stroke data');
        SetFocus(EditorSurface); CtrlKey(Ord('Z'));
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=EditingInitialCount,'Native undo stroke count');
        Check(not TFile.Exists(EditingFile),'Native undo did not restore inferred state');
        CtrlKey(Ord('Y'));
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=EditingInitialCount+1,'Native redo stroke count');
        Check(TFile.Exists(EditingFile),'Native redo did not persist learning');
        SetNativeStrokeSelection([EditingSelectedStroke,EditingSelectedStroke+1]);
        Check(SendMessage(EditingStrokeList,LB_GETSELCOUNT,0,0)=2,'Multiple row selection failed');
        CaptureDialog('ui_multi_selection.png'); EditingStage:=7; PostContext(EditingStrokeList,Point(80,30));
      end;
      7: begin
        Menu:=OpenPopupHandle; Check(GetMenuItemCount(Menu)>=8,'Stroke popup missing actions');
        CaptureWindow(PopupWindow,'ui_stroke_menu.png'); EditingStage:=8; ChoosePopupItem(0);
      end;
      8: begin
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=EditingInitialCount,'Native endpoint join failed');
        CaptureDialog('ui_edit_joined.png'); SetFocus(EditingStrokeList); CtrlKey(Ord('Z')); CtrlKey(Ord('Z'));
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=EditingInitialCount,'Native undo split/join sequence');
        Check(not TFile.Exists(EditingFile),'Native history left test learning behind');
        EditingClick(EditingPoint); CtrlKey(Ord('K')); EditingClick(EditingSecondPoint); CtrlKey(Ord('K'));
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=EditingInitialCount+2,'Cannot prepare multiple strokes for drag test');
        EditingBeforeDragHash:=THashSHA2.GetHashStringFromFile(EditingFile);
        EditingStage:=9; StartNativeGroupDrag; CaptureDialog('ui_drag_insert.png');
        // キャプチャ中にイベントループへ戻らず、利用者のマウス移動の影響を受ける前にドロップする。
        SendMessage(EditingDragCapture,WM_MOUSEMOVE,MK_LBUTTON,EditingDragPosition);
        SendMessage(EditingDragCapture,WM_LBUTTONUP,0,EditingDragPosition);
        SetWindowPos(DialogHandle,HWND_NOTOPMOST,0,0,0,0,SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
      end;
      9: begin
        Check(THashSHA2.GetHashStringFromFile(EditingFile)<>EditingBeforeDragHash,'Drag did not reorder selected rows');
        SetFocus(EditingStrokeList); CtrlKey(Ord('Z'));
        Check(THashSHA2.GetHashStringFromFile(EditingFile)=EditingBeforeDragHash,'Undo did not restore drag order');
        CtrlKey(Ord('Z')); CtrlKey(Ord('Z'));
        Check(not TFile.Exists(EditingFile),'Native drag test did not clean up learning');
        KillTimer(0,EditingTimer); EditingTimer:=0; EditingStage:=10; PostMessage(DialogHandle,WM_CLOSE,0,0);
      end;
    end;
  except
    on E: Exception do
    begin
      EditingError:=Format('stage %d: %s',[EditingStage,E.Message]); EndMenu; KillTimer(0,EditingTimer); EditingTimer:=0;
      if GetCapture<>0 then SendMessage(GetCapture,WM_RBUTTONUP,0,0);
      if DialogHandle<>0 then SetWindowPos(DialogHandle,HWND_NOTOPMOST,0,0,0,0,SWP_NOMOVE or SWP_NOSIZE or SWP_NOACTIVATE);
      if DialogHandle<>0 then PostMessage(DialogHandle,WM_CLOSE,0,0);
    end;
  end;
end;

procedure TestNativeStrokeEditing;
var S: TWritingSettings; Engine: TWritingFontEngine; Glyph: TWritingGlyph;
  Edit: TEDIT_SECTION; I,J,Segment,First,Last: Integer; Vertices: TArray<Integer>;
  Folder: string; HadFolder: Boolean; Best: Double;
begin
  S:=DefaultWritingSettings; S.FontName:='ＭＳ ゴシック'; Engine:=TWritingFontEngine.Create;
  Folder:=''; HadFolder:=True; EditingFile:='';
  try
    Engine.Configure(S); Folder:=TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),Engine.FontID);
    HadFolder:=TDirectory.Exists(Folder); EditingFile:='';
    // 未使用の私用文字だけを使う。既存の文字の学習ファイルへは一切書き込まない。
    for I:=$E100 to $E1FF do
    begin
      EditingFile:=TPath.Combine(Folder,IntToHex(I,4)+'.json');
      if not TFile.Exists(EditingFile) then begin S.Text:=Char(I); Break end;
      EditingFile:='';
    end;
    Check(EditingFile<>'','No unused native editing test character');
    Glyph:=Engine.Glyph(S.Text); EditingInitialCount:=Length(Glyph.Strokes);
    EditingFontID:=Engine.FontID; EditingCharacter:=S.Text;
    Check(EditingInitialCount>0,'Native editing test glyph has no strokes');
    EditingSelectedStroke:=-1;
    for I:=0 to High(Glyph.Strokes) do
      if (Length(Glyph.Strokes[I].Points)>=3) and (Glyph.Strokes[I].Length>8) then
      begin EditingSelectedStroke:=I; Break end;
    Check(EditingSelectedStroke>=0,'Native editing test glyph has no splittable path');
    EditingFirst:=Glyph.Strokes[EditingSelectedStroke].Points[0];
    EditingLast:=Glyph.Strokes[EditingSelectedStroke].Points[High(Glyph.Strokes[EditingSelectedStroke].Points)];
    Vertices:=EditingVertices(Glyph.Strokes[EditingSelectedStroke]); Best:=-1; First:=0; Last:=High(Glyph.Strokes[EditingSelectedStroke].Points);
    for I:=1 to High(Vertices) do
    begin
      var Span: Double; Span:=0;
      for J:=Vertices[I-1]+1 to Vertices[I] do Span:=Span+Distance(Glyph.Strokes[EditingSelectedStroke].Points[J-1],Glyph.Strokes[EditingSelectedStroke].Points[J]);
      if Span>Best then begin Best:=Span; First:=Vertices[I-1]; Last:=Vertices[I] end;
    end;
    Segment:=Min(Last-1,First+(Last-First) div 3);
    EditingGlyphPoint:=PointF(
      (Glyph.Strokes[EditingSelectedStroke].Points[Segment].X+Glyph.Strokes[EditingSelectedStroke].Points[Segment+1].X)/2,
      (Glyph.Strokes[EditingSelectedStroke].Points[Segment].Y+Glyph.Strokes[EditingSelectedStroke].Points[Segment+1].Y)/2);
    var A,B: TPointF; var Len: Double;
    A:=Glyph.Strokes[EditingSelectedStroke].Points[Segment]; B:=Glyph.Strokes[EditingSelectedStroke].Points[Segment+1];
    Len:=Max(1E-6,Distance(A,B)); EditingNormal:=PointF(-(B.Y-A.Y)/Len,(B.X-A.X)/Len);
    Segment:=Min(Last-1,First+(Last-First)*2 div 3);
    EditingGlyphSecondPoint:=Glyph.Strokes[EditingSelectedStroke].Points[Segment];
    EditingGlyphWidth:=Glyph.Width; EditingGlyphHeight:=Glyph.Height;
    Configure(S); UIValues[0]:=UTF8String(DetailBacking); UIValues[1]:=UTF8String(TextBacking);
    UIValues[2]:='万年筆'; UIValues[3]:='240'; UIValues[4]:='35'; UIValues[5]:='-100'; UIValues[6]:='-100'; UIValues[7]:='100'; FillChar(Edit,SizeOf(Edit),0);
    Edit.GetObjectItemValue:=UIGet; Edit.SetObjectItemValue:=UISet;
    DialogHandle:=0; PreviewSurface:=0; EditorSurface:=0; EditingStrokeList:=0;
    EditingStage:=0; EditingTicks:=0; EditingError:=''; EditingPoint:=Point(0,0);
    EditingTimer:=SetTimer(0,0,250,@EditingTick); Check(EditingTimer<>0,'Cannot start native edit timer');
    try Button^.Callback2(@Edit,Pointer(1234),'自動筆記:2','設定')
    finally if EditingTimer<>0 then KillTimer(0,EditingTimer) end;
    Check(EditingError='','Native stroke editing failure: '+EditingError);
    Check(EditingStage=10,'Native stroke editing did not finish');
    Writeln('PASS thick selected stroke, point direction reversal, popups, join, drag insertion, shortcuts and cleanup');
  finally
    Engine.Free;
    if (EditingFile<>'') and TFile.Exists(EditingFile) then TFile.Delete(EditingFile);
    if (Folder<>'') and not HadFolder and TDirectory.Exists(Folder) and (Length(TDirectory.GetFiles(Folder))=0) then
      TDirectory.Delete(Folder,False);
  end;
end;

procedure CheckSavedBranch;
var G: TWritingGlyph; Warning: string;
begin
  G:=TWritingGlyph.Create;
  try
    G.FontID:=BranchFontID; G.Character:=BranchCharacter; G.Width:=BranchWidth; G.Height:=BranchHeight;
    Check(LoadGlyphLearning(G,Warning) and (Warning=''),'Native branch result was not saved');
    CheckAbsorbedBranch(G,PointF(14,7),PointF(30,34));
  finally G.Free end;
end;

procedure BranchTick(Wnd: HWND; Msg: UINT; Event: UINT_PTR; Time: DWORD); stdcall;
var Header: TNMHdr;
begin
  Inc(BranchTicks);
  try
    if DialogHandle=0 then EnumThreadWindows(GetCurrentThreadId,@FindUIWindow,0);
    if BranchTicks>30 then raise Exception.Create('Native branch test timed out');
    if DialogHandle=0 then Exit;
    case BranchStage of
      0: begin
        UIStage:=0; EnumChildWindows(DialogHandle,@FindUIChild,0);
        SendMessage(PageHandle,TCM_SETCURSEL,1,0);
        FillChar(Header,SizeOf(Header),0); Header.hwndFrom:=PageHandle; Header.code:=TCN_SELCHANGE;
        SendMessage(GetParent(PageHandle),WM_NOTIFY,0,LPARAM(@Header)); BranchStage:=1;
      end;
      1: begin
        UIStage:=3; EnumChildWindows(DialogHandle,@FindUIChild,0);
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=3,'Native branch fixture has the wrong stroke count');
        SetNativeStrokeSelection([0,2]); CaptureDialog('ui_branch_before.png');
        BranchStage:=2; PostContext(EditingStrokeList,Point(80,30));
      end;
      2: begin
        OpenPopupHandle; BranchStage:=3; ChoosePopupItem(0);
      end;
      3: begin
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=2,'Existing Join menu did not absorb the branch');
        CheckSavedBranch; CaptureDialog('ui_branch_absorbed.png');
        SetFocus(EditingStrokeList); CtrlKey(Ord('Z'));
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=3,'Undo did not restore the separate branch');
        Check(THashSHA2.GetHashStringFromFile(BranchFile)=BranchBeforeHash,'Undo changed the original branch learning');
        CaptureDialog('ui_branch_undo.png'); BranchStage:=4;
      end;
      4: begin
        SetFocus(EditingStrokeList); CtrlKey(Ord('Y'));
        Check(SendMessage(EditingStrokeList,LB_GETCOUNT,0,0)=2,'Redo did not absorb the branch');
        CheckSavedBranch; CaptureDialog('ui_branch_redone.png');
        KillTimer(0,BranchTimer); BranchTimer:=0; BranchStage:=5; PostMessage(DialogHandle,WM_CLOSE,0,0);
      end;
    end;
  except on E: Exception do
  begin
    BranchError:=Format('stage %d: %s',[BranchStage,E.Message]); EndMenu;
    KillTimer(0,BranchTimer); BranchTimer:=0; if DialogHandle<>0 then PostMessage(DialogHandle,WM_CLOSE,0,0);
  end end;
end;

procedure TestNativeBranchJoin;
var S: TWritingSettings; Engine: TWritingFontEngine; Source,G: TWritingGlyph;
  Folder: string; HadFolder: Boolean; I: Integer; Edit: TEDIT_SECTION;
begin
  Engine:=TWritingFontEngine.Create; G:=TWritingGlyph.Create; Folder:=''; HadFolder:=True; BranchFile:='';
  try
    S:=DefaultWritingSettings; S.FontName:='ＭＳ ゴシック'; Engine.Configure(S);
    Folder:=TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),Engine.FontID); HadFolder:=TDirectory.Exists(Folder);
    for I:=$E200 to $E2FF do
    begin
      BranchFile:=TPath.Combine(Folder,IntToHex(I,4)+'.json');
      if not TFile.Exists(BranchFile) then begin S.Text:=Char(I); Break end;
      BranchFile:='';
    end;
    Check(BranchFile<>'','No unused branch test character'); Source:=Engine.Glyph(S.Text);
    G.FontID:=Engine.FontID; G.FontFace:=Source.FontFace; G.Character:=S.Text;
    G.Width:=Source.Width; G.Height:=Source.Height; G.Mask:=Copy(Source.Mask);
    MakeBranchFixture(G,True); SaveGlyphLearning(G); BranchBeforeHash:=THashSHA2.GetHashStringFromFile(BranchFile);
    BranchFontID:=G.FontID; BranchCharacter:=G.Character; BranchWidth:=G.Width; BranchHeight:=G.Height;
    Configure(S); UIValues[0]:=UTF8String(DetailBacking); UIValues[1]:=UTF8String(TextBacking);
    UIValues[2]:='万年筆'; UIValues[3]:='240'; UIValues[4]:='35'; UIValues[5]:='-100'; UIValues[6]:='-100'; UIValues[7]:='100'; FillChar(Edit,SizeOf(Edit),0);
    Edit.GetObjectItemValue:=UIGet; Edit.SetObjectItemValue:=UISet;
    DialogHandle:=0; PageHandle:=0; EditorSurface:=0; EditingStrokeList:=0;
    BranchStage:=0; BranchTicks:=0; BranchError:=''; BranchTimer:=SetTimer(0,0,250,@BranchTick);
    Check(BranchTimer<>0,'Cannot start native branch timer');
    try Button^.Callback2(@Edit,Pointer(1234),'自動筆記:2','設定')
    finally if BranchTimer<>0 then KillTimer(0,BranchTimer) end;
    Check(BranchError='','Native branch join failure: '+BranchError);
    Check(BranchStage=5,'Native branch join did not finish');
    Writeln('PASS existing native Join menu absorbs a branch, saves, undoes and redoes');
  finally
    G.Free; Engine.Free;
    if (BranchFile<>'') and TFile.Exists(BranchFile) then TFile.Delete(BranchFile);
    if (Folder<>'') and not HadFolder and TDirectory.Exists(Folder) and (Length(TDirectory.GetFiles(Folder))=0) then TDirectory.Delete(Folder,False);
  end;
end;

procedure RenderDemo;
var S: TWritingSettings; I,J,FrameCount: Integer; Duration,Time: Double; A: TWritingPixels;
begin
  S:=DefaultWritingSettings; S.Text:='自動筆記'+sLineBreak+'文字が、動き出す。'; S.FontSize:=64;
  S.InkColor:=$000000; // 説明書用だけ黒文字に固定する。本体の白い初期値は変更しない。
  S.Speed:=240; Duration:=Renderer.Duration(S); S.Speed:=S.Speed*Duration/6;
  Configure(S); Duration:=Renderer.Duration(S); SizeFrame(800,450);
  SetLength(HostInput,Scene.Width*Scene.Height);
  for J:=0 to High(HostInput) do
  begin HostInput[J].R:=255; HostInput[J].G:=255; HostInput[J].B:=255; HostInput[J].A:=255 end;
  ForceDirectories(TPath.Combine(OutputDirectory,'DemoFrames')); FrameCount:=Ceil((Duration+1.4)*20);
  for I:=0 to FrameCount do
  begin
    Time:=I/20; A:=Render(Time);
    SavePNG(A,Scene.Width,Scene.Height,Format('DemoFrames/frame_%3.3d.png',[I]));
  end;
  HostInput:=nil; Writeln(Format('DEMO %d frames at 20 fps; writing %.3f seconds',[FrameCount+1,Duration]));
end;

procedure RenderGlyphSamples;
var S: TWritingSettings; I,J: Integer; PG: TPlacedGlyph; Time: Double; A: TWritingPixels; Timing: TStringList;
begin
  S:=DefaultWritingSettings; S.Text:='自'; S.FontSize:=150; S.Speed:=240;
  S.InkColor:=$202028; // 露出方式の比較は両バージョンとも黒文字・白背景へそろえる。
  if ParamCount>=4 then S.Text:=ParamStr(4);
  Configure(S); Renderer.Prepare(S); PG:=Renderer.PlacedGlyphs[High(Renderer.PlacedGlyphs)]; SizeFrame(420,420);
  SetLength(HostInput,Scene.Width*Scene.Height);
  for J:=0 to High(HostInput) do
  begin HostInput[J].R:=255; HostInput[J].G:=255; HostInput[J].B:=255; HostInput[J].A:=255 end;
  ForceDirectories(TPath.Combine(OutputDirectory,'GlyphSamples')); Timing:=TStringList.Create;
  try
    for I:=0 to High(PG.Glyph.Strokes) do
    begin
      Time:=(PG.StartDistance+(PG.Glyph.Strokes[I].StartDistance+PG.Glyph.Strokes[I].Length)*PG.Scale)/S.Speed;
      A:=Render(Max(0,Time-1E-5));
      SavePNG(A,Scene.Width,Scene.Height,Format('GlyphSamples/stroke_%2.2d.png',[I+1]));
      Timing.Add(Format('stroke_%2.2d=%.6f',[I+1,Time],TFormatSettings.Invariant));
      S.ShowPen:=False; Configure(S); A:=Render(Max(0,Time-1E-5));
      SavePNG(A,Scene.Width,Scene.Height,Format('GlyphSamples/ink_%2.2d.png',[I+1]));
      if I<High(PG.Glyph.Strokes) then
        Time:=(PG.StartDistance+(PG.Glyph.Strokes[I].StartDistance+PG.Glyph.Strokes[I].Length+
          PG.Glyph.Strokes[I+1].StartDistance)*0.5*PG.Scale)/S.Speed;
      A:=Render(Time); SavePNG(A,Scene.Width,Scene.Height,Format('GlyphSamples/lift_%2.2d.png',[I+1]));
      Time:=(PG.StartDistance+(PG.Glyph.Strokes[I].StartDistance+PG.Glyph.Strokes[I].Length*0.08)*PG.Scale)/S.Speed;
      A:=Render(Time); SavePNG(A,Scene.Width,Scene.Height,Format('GlyphSamples/start_%2.2d.png',[I+1]));
      S.ShowPen:=True; Configure(S);
    end;
    A:=Render(Renderer.Duration(S)+1); SavePNG(A,Scene.Width,Scene.Height,'GlyphSamples/complete.png');
    Timing.SaveToFile(TPath.Combine(OutputDirectory,'GlyphSamples/timing.txt'),TEncoding.UTF8);
    SetLength(A,Length(PG.Glyph.Mask));
    for I:=0 to High(A) do
    begin A[I].R:=255-PG.Glyph.Mask[I]; A[I].G:=A[I].R; A[I].B:=A[I].R; A[I].A:=255 end;
    SavePNG(A,PG.Glyph.Width,PG.Glyph.Height,'GlyphSamples/mask.png');
  finally Timing.Free; HostInput:=nil end;
  Writeln('Created production glyph samples: ',Length(PG.Glyph.Strokes),' strokes');
end;

var Module: HMODULE; GetTable: TGetTable; Init: TInitialize; Required: TRequired;
  Uninit: TUninitialize; Session: Pointer; PenTests: TPenTestContext;
begin
  Module:=0; Renderer:=nil; Session:=nil;
  try
    if ParamCount<2 then raise Exception.Create('Usage: AutoWriting_Tests.exe plugin.auf2 output-directory');
    OutputDirectory:=ExpandFileName(ParamStr(2)); ForceDirectories(OutputDirectory);
    if not ((ParamCount>=3) and ((ParamStr(3)='--glyph-samples') or (ParamStr(3)='--demo-only'))) then
    begin TestSettingsAndLearning; TestStrokeEditing; TestEditingVertices; TestOverlappingReveal; TestSelectedStrokeOperations; TestBranchAbsorption; TestFontCacheAndLayout end;
    Module:=LoadLibrary(PChar(ExpandFileName(ParamStr(1))));
    Check(Module<>0,'Cannot load production AUF2: '+SysErrorMessage(GetLastError));
    @GetTable:=GetProcAddress(Module,'GetFilterPluginTable'); @Init:=GetProcAddress(Module,'InitializePlugin');
    @Required:=GetProcAddress(Module,'RequiredVersion'); @Uninit:=GetProcAddress(Module,'UninitializePlugin');
    Check(Assigned(GetTable) and Assigned(Init) and Assigned(Required) and Assigned(Uninit),'Missing exports');
    Check(GetProcAddress(Module,'ReadWritingRenderProfile')=nil,'Normal build must not expose profiling controls');
    Check(Required=2011600,'Minimum SDK version'); Check(Init(2011500)=0,'Old host accepted'); Check(Init(2011600)=1,'Supported host rejected');
    Table:=GetTable; Check(Table<>nil,'No table'); Check(string(Table^.Name)='自動筆記','Plugin name');
    Check(string(Table^.Information)='自動筆記 / SYNC_AutoWriting v'+AW_VERSION,'Plugin display version differs from the source version');
    Check(string(Table^.Label_)='SYNC','Group'); Check(Table^.Flag=25,'Plugin flags'); Bind;
    Renderer:=TWritingRenderer.Create; Session:=Table^.Func_Create(42); Check(Session<>nil,'Create session');
    FillChar(Video,SizeOf(Video),0); FillChar(Obj,SizeOf(Obj),0); FillChar(Scene,SizeOf(Scene),0);
    Scene.Rate:=30; Scene.Scale:=1; Video.Scene:=@Scene; Video.Object_:=@Obj;
    Video.GetImageData:=GetImage; Video.SetImageData:=SetImage; Video.UserData:=Session;
    PenTests.Check:=Check; PenTests.Configure:=Configure; PenTests.Render:=Render; PenTests.SizeFrame:=SizeFrame;
    PenTests.SavePNG:=SavePNG; PenTests.Renderer:=Renderer; PenTests.PenSizeTrack:=Tracks[8];
    PenTests.DetailsItem:=DetailsItem;
    PenTests.PenItem:=PenItem;
    if (ParamCount>=3) and (ParamStr(3)='--glyph-samples') then RenderGlyphSamples
    else if (ParamCount>=3) and (ParamStr(3)='--demo-only') then RenderDemo
    else begin TestFinalFont; TestPenRendering(PenTests); TestProduction; TestSettingsDialog; TestNativeStrokeEditing; TestNativeBranchJoin end;
    if (ParamCount>=3) and (ParamStr(3)='--demo') then begin Video.UserData:=Session; RenderDemo end;
    Writeln('ALL PASS: ',Tests,' checks');
  except on E: Exception do begin Writeln('FAIL ',E.ClassName,': ',E.Message); ExitCode:=1 end end;
  if Session<>nil then Table^.Func_Destroy(42,Session);
  Renderer.Free; if Module<>0 then begin if Assigned(Uninit) then Uninit; FreeLibrary(Module) end;
end.
