unit AutoWriting_Learning;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// マイドキュメントにフォント×文字の補正経路を永続保存する。
// フォントファイル・元輪郭・ラスターマスクは保存しない。保存は原子的に置換する。

interface

uses AutoWriting_Types;

function LearningDirectory: string;
function LearningRevision: Integer;
// 正常な学習だけを反映する。破損データは変更せず、Warningへ理由を返す。
function LoadGlyphLearning(Glyph: TWritingGlyph; out Warning: string): Boolean;
// 保存失敗は例外。呼出側UIがユーザーへ通知する。成功時に共有リビジョンを更新する。
procedure SaveGlyphLearning(Glyph: TWritingGlyph);
procedure DeleteGlyphLearning(Glyph: TWritingGlyph; Reestimate: Boolean=True);

implementation

uses System.SysUtils, System.Classes, System.IOUtils, System.JSON,
  System.Types, System.Math, System.SyncObjs, System.Generics.Collections, Winapi.Windows,
  AutoWriting_Inference;

var Lock: TCriticalSection; Revision: Integer;

function LearningDirectory: string;
begin Result:=TPath.Combine(TPath.GetDocumentsPath,'SYNC_AutoWriting') end;

function LearningRevision: Integer;
begin Result:=TInterlocked.CompareExchange(Revision,0,0) end;

function GlyphFile(Glyph: TWritingGlyph): string;
var C: Char; Code: string;
begin
  if Length(Glyph.FontID)<>64 then raise EArgumentException.Create('Invalid font identifier');
  for C in Glyph.FontID do if not CharInSet(C,['0'..'9','a'..'f','A'..'F']) then
    raise EArgumentException.Create('Invalid font identifier');
  Code:=''; for C in Glyph.Character do Code:=Code+IntToHex(Ord(C),4);
  if Code='' then raise EArgumentException.Create('Empty character');
  Result:=TPath.Combine(TPath.Combine(TPath.Combine(LearningDirectory,'Fonts'),Glyph.FontID),Code+'.json');
end;

function LoadGlyphLearning(Glyph: TWritingGlyph; out Warning: string): Boolean;
var FileName: string; V: TJSONValue; J,O: TJSONObject; A,P,XY,Vertices: TJSONArray;
  I,K,Total,Index: Integer; Paths: TArray<TStroke>; X,Y: Double;
begin
  Result:=False; Warning:=''; V:=nil; Lock.Acquire;
  try
    try
      FileName:=GlyphFile(Glyph); if not TFile.Exists(FileName) then Exit;
      if TFile.GetSize(FileName)>4*1024*1024 then raise EConvertError.Create('Learning file is too large');
      V:=TJSONObject.ParseJSONValue(TFile.ReadAllText(FileName,TEncoding.UTF8));
      if not (V is TJSONObject) then raise EConvertError.Create('Invalid learning JSON'); J:=TJSONObject(V);
      if (J.GetValue<Integer>('schema',0)<>1) or (J.GetValue<Integer>('em',0)<>AW_EM) or
        (J.GetValue<string>('fontID','')<>Glyph.FontID) or
        (J.GetValue<string>('character','')<>Glyph.Character) then raise EConvertError.Create('Learning identity mismatch');
      A:=J.GetValue<TJSONArray>('strokes');
      if (A=nil) or (A.Count=0) or (A.Count>1024) then raise EConvertError.Create('Invalid stroke count');
      SetLength(Paths,A.Count); Total:=0;
      for I:=0 to A.Count-1 do
      begin
        if not (A.Items[I] is TJSONObject) then raise EConvertError.Create('Invalid stroke');
        O:=TJSONObject(A.Items[I]); Paths[I].ID:=O.GetValue<Integer>('id',I);
        Paths[I].Reversed:=O.GetValue<Boolean>('reversed',False); P:=O.GetValue<TJSONArray>('points');
        if (P=nil) or (P.Count<2) or (P.Count>8192) then raise EConvertError.Create('Invalid path');
        Inc(Total,P.Count); if Total>65536 then raise EConvertError.Create('Too many path points');
        SetLength(Paths[I].Points,P.Count);
        for K:=0 to P.Count-1 do
        begin
          if not (P.Items[K] is TJSONArray) then raise EConvertError.Create('Invalid coordinate');
          XY:=TJSONArray(P.Items[K]); if XY.Count<>2 then raise EConvertError.Create('Invalid coordinate');
          X:=XY.Items[0].AsType<Double>*AW_EM; Y:=XY.Items[1].AsType<Double>*AW_EM;
          if IsNan(X) or IsInfinite(X) or IsNan(Y) or IsInfinite(Y) or
            (X< -32) or (Y< -32) or (X>Glyph.Width+32) or (Y>Glyph.Height+32) then
            raise EConvertError.Create('Path coordinate outside glyph');
          Paths[I].Points[K]:=PointF(X,Y);
        end;
        Vertices:=O.GetValue<TJSONArray>('vertices',nil);
        if Vertices<>nil then
        begin
          if Vertices.Count>P.Count then raise EConvertError.Create('Too many editing vertices');
          SetLength(Paths[I].PinnedVertices,Vertices.Count);
          for K:=0 to Vertices.Count-1 do
          begin
            Index:=Vertices.Items[K].AsType<Integer>;
            if (Index<0) or (Index>=P.Count) then raise EConvertError.Create('Invalid editing vertex');
            if (K>0) and (Index<=Paths[I].PinnedVertices[K-1]) then raise EConvertError.Create('Unordered editing vertices');
            Paths[I].PinnedVertices[K]:=Index;
          end;
        end;
      end;
      Glyph.Strokes:=Paths; Glyph.Learned:=True; PrepareGlyphTiming(Glyph); Result:=True;
    except on E: Exception do Warning:=Glyph.Character+': '+E.Message end;
  finally V.Free; Lock.Release end;
end;

procedure SaveGlyphLearning(Glyph: TWritingGlyph);
var J,O: TJSONObject; A,P,XY,Vertices: TJSONArray; I,K: Integer; FileName,TempName: string;
begin
  if Length(Glyph.Strokes)=0 then Exit;
  J:=TJSONObject.Create; Lock.Acquire; TempName:='';
  try
    J.AddPair('schema',TJSONNumber.Create(1)); J.AddPair('em',TJSONNumber.Create(AW_EM));
    J.AddPair('fontID',Glyph.FontID); J.AddPair('fontFace',Glyph.FontFace); J.AddPair('character',Glyph.Character);
    A:=TJSONArray.Create; J.AddPair('strokes',A);
    for I:=0 to High(Glyph.Strokes) do
    begin
      O:=TJSONObject.Create; A.AddElement(O); O.AddPair('id',TJSONNumber.Create(Glyph.Strokes[I].ID));
      O.AddPair('reversed',TJSONBool.Create(Glyph.Strokes[I].Reversed)); P:=TJSONArray.Create; O.AddPair('points',P);
      for K:=0 to High(Glyph.Strokes[I].Points) do
      begin
        XY:=TJSONArray.Create; XY.Add(Glyph.Strokes[I].Points[K].X/AW_EM);
        XY.Add(Glyph.Strokes[I].Points[K].Y/AW_EM); P.AddElement(XY);
      end;
      if Length(Glyph.Strokes[I].PinnedVertices)>0 then
      begin
        Vertices:=TJSONArray.Create; O.AddPair('vertices',Vertices);
        for K in Glyph.Strokes[I].PinnedVertices do Vertices.Add(K);
      end;
    end;
    FileName:=GlyphFile(Glyph); ForceDirectories(ExtractFilePath(FileName));
    TempName:=FileName+'.'+TGUID.NewGuid.ToString+'.tmp';
    TFile.WriteAllText(TempName,J.ToJSON,TEncoding.UTF8);
    if not MoveFileEx(PChar(TempName),PChar(FileName),MOVEFILE_REPLACE_EXISTING or MOVEFILE_WRITE_THROUGH) then RaiseLastOSError;
    TempName:=''; Glyph.Learned:=True; TInterlocked.Increment(Revision);
  finally
    try
      if (TempName<>'') and TFile.Exists(TempName) then
        try TFile.Delete(TempName)
        except on E: Exception do OutputDebugString(PChar('SYNC_AutoWriting temporary learning file: '+E.Message)) end;
    finally Lock.Release; J.Free end;
  end;
end;

procedure DeleteGlyphLearning(Glyph: TWritingGlyph; Reestimate: Boolean);
var FileName: string;
begin
  Lock.Acquire;
  try
    FileName:=GlyphFile(Glyph); if TFile.Exists(FileName) then TFile.Delete(FileName);
    Glyph.Learned:=False;
    if Reestimate then InferGlyphStrokes(Glyph);
    TInterlocked.Increment(Revision);
  finally Lock.Release end;
end;

initialization
  Lock:=TCriticalSection.Create;
finalization
  Lock.Free;
end.
