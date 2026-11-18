unit AutoWriting_EditRegressionTests;

// Copyright (c) 2026 VRAMの魔術師 / SPDX-License-Identifier: GPL-3.0-only
// 結合で長い曲線を失わないこと、頂点と画の削除・履歴・空の学習を検査する。
interface

type TEditRegressionCheck = procedure(Value: Boolean; const MessageText: string);
procedure TestEditRegressions(Check: TEditRegressionCheck);

implementation

uses System.SysUtils, System.Types, System.Hash, System.IOUtils,
  AutoWriting_Types, AutoWriting_Editing, AutoWriting_Vertices,
  AutoWriting_Branches, AutoWriting_Inference, AutoWriting_Learning;

procedure TestEditRegressions(Check: TEditRegressionCheck);
var G,Loaded: TWritingGlyph; A,B,Original,Moved: TStroke; State: TGlyphEditState;
  Attachment: TStrokeBranch; Index,I,J,Side,Row: Integer; P: TPointF; Found: Boolean;
  Folder,FileName,Warning: string;
begin
  G:=TWritingGlyph.Create; Loaded:=TWritingGlyph.Create; Folder:=''; FileName:='';
  try
    G.Width:=128; G.Height:=128;
    // 「き」の斜線の途中へ接続する長い下側の曲線。枝先への置換でV字になる退行例。
    A:=Default(TStroke); A.ID:=40;
    A.Points:=[PointF(48,48),PointF(49,52),PointF(53,59),PointF(57,65),PointF(59,70),
      PointF(59,72),PointF(60,72),PointF(60,73),PointF(61,74),PointF(62,74),PointF(62,75),PointF(63,76)];
    B:=Default(TStroke); B.ID:=41; B.PinnedVertices:=[4];
    B.Points:=[PointF(59,72),PointF(40,70),PointF(26,70),PointF(13,76),PointF(10,84),
      PointF(12,93),PointF(24,100),PointF(48,102)];
    Check(not FindStrokeBranch(A,B,Attachment),'A long curved stroke must not be absorbed as a spur');
    for Row:=0 to 1 do for Side:=0 to 3 do
    begin
      G.Strokes:=[A,B]; if Row=1 then G.Strokes:=[B,A];
      if Side and 1<>0 then ReverseGlyphStroke(G,0);
      if Side and 2<>0 then ReverseGlyphStroke(G,1);
      State:=CaptureGlyphState(G);
      Check(JoinSelectedStrokes(G,[0,1],Index),'Cannot join a curve near an endpoint');
      Check((Length(G.Strokes)=1) and (Index=0),'Curve join result count');
      for Original in State.Strokes do for P in Original.Points do
      begin
        Found:=False;
        for I:=0 to High(G.Strokes[0].Points) do if Distance(P,G.Strokes[0].Points[I])<1E-5 then Found:=True;
        Check(Found,'Joining lost original curve geometry');
      end;
    end;

    Original:=Default(TStroke); Original.ID:=8;
    Original.Points:=[PointF(0,0),PointF(2,4),PointF(5,8),PointF(8,4),PointF(10,0)];
    Original.PinnedVertices:=[0,2,4]; A:=Original;
    Check(DeletePathVertex(A,2),'Cannot delete a corner vertex');
    Check((Length(A.Points)=2) and (A.Points[0]=Original.Points[0]) and
      (A.Points[1]=Original.Points[4]),'Deleted corner was not replaced by the neighboring segment');
    Check((Length(A.PinnedVertices)=2) and (A.PinnedVertices[1]=1),'Deleted vertex pin remapping');
    Check((Length(Original.Points)=5) and (Length(Original.PinnedVertices)=3),'Vertex deletion modified a shared original');
    Check(not DeletePathVertex(A,0),'Deleting a two-vertex stroke must use stroke deletion');
    A:=Original; Check(DeletePathVertex(A,0),'Cannot trim the first vertex');
    Check(A.Points[0]=Original.Points[2],'First vertex deletion did not trim to the next control point');
    A:=Original; Check(DeletePathVertex(A,4),'Cannot trim the last vertex');
    Check(A.Points[High(A.Points)]=Original.Points[2],'Last vertex deletion did not trim to the previous control point');
    Original.Points:=[PointF(0,0),PointF(5,0),PointF(10,0)]; Original.PinnedVertices:=nil;
    Check(MovePathVertex(Original,1,PointF(5,6),Moved),'Cannot move a vertex');
    Check((Moved.Points[1]=PointF(5,6)) and (Original.Points[1]=PointF(5,0)),'Vertex move did not preserve its original');
    Check((Length(Moved.PinnedVertices)=1) and (Moved.PinnedVertices[0]=1),'Moved vertex must remain available for the next drag');

    A:=Original; A.ID:=10; B:=Default(TStroke); B.ID:=11;
    B.Points:=[PointF(15,15),PointF(15,15)]; Moved.ID:=12;
    G.Strokes:=[A,B,Moved]; G.Learned:=False; State:=CaptureGlyphState(G);
    Check(DeleteSelectedStrokes(G,[1],Index),'Cannot delete a dot-only stroke');
    Check((Length(G.Strokes)=2) and (G.Strokes[0].ID=10) and (G.Strokes[1].ID=12),
      'Stroke deletion changed unrelated identities or ordering');
    RestoreGlyphState(G,State);
    Check((Length(G.Strokes)=3) and (G.Strokes[1].ID=11),'Undo did not restore the dot-only stroke');
    Check(not DeleteSelectedStrokes(G,[0,0],Index),'Duplicate stroke selection must be rejected');
    Check(not DeleteSelectedStrokes(G,[3],Index),'Invalid stroke selection must be rejected');
    Check(DeleteSelectedStrokes(G,[2,0,1],Index) and (Index=-1) and (Length(G.Strokes)=0),'Cannot delete all strokes');
    G.FontID:=THashSHA2.GetHashString('Delete stroke verification '+TGUID.NewGuid.ToString);
    G.Character:='検'; G.FontFace:='Editing regression';
    Folder:=TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),G.FontID); FileName:=TPath.Combine(Folder,'691C.json');
    SaveGlyphLearning(G); Loaded.FontID:=G.FontID; Loaded.Character:=G.Character;
    Loaded.Width:=G.Width; Loaded.Height:=G.Height;
    Check(LoadGlyphLearning(Loaded,Warning) and Loaded.Learned and (Warning='') and
      (Length(Loaded.Strokes)=0),'An empty edited glyph must persist without being inferred again');
    RestoreGlyphState(G,State);
    for I:=0 to High(G.Strokes) do for J:=0 to High(G.Strokes[I].Points) do
      Check(G.Strokes[I].Points[J]=State.Strokes[I].Points[J],'Deletion history did not restore original geometry');
    Writeln('PASS curved joins, vertex deletion and drag pinning, dot/all-stroke deletion, history and empty learning');
  finally
    Loaded.Free; G.Free;
    if (FileName<>'') and TFile.Exists(FileName) then TFile.Delete(FileName);
    if (Folder<>'') and TDirectory.Exists(Folder) then TDirectory.Delete(Folder,False);
  end;
end;

end.
