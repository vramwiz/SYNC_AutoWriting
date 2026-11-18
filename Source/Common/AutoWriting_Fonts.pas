unit AutoWriting_Fonts;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// Windowsのインストール済みアウトラインフォントを参照し、128 emで解析する。
// DC・HFONT・文字キャッシュはエンジン所有。ホストやUIのポインターを保持しない。

interface

uses System.SysUtils, System.Generics.Collections, Winapi.Windows, AutoWriting_Types;

type
  TWritingFontEngine = class
  private
    FDC: HDC;
    FFont: HFONT;
    FOldFont: HGDIOBJ;
    FKey, FFontID, FFace, FWarnings: string;
    FCache: TObjectDictionary<string,TWritingGlyph>;
    FRevision: Integer;
    function CreateGlyph(const Character: string): TWritingGlyph;
  public
    constructor Create;
    destructor Destroy; override;
    // フォント・学習の変更時だけキャッシュを無効化する。
    procedure Configure(const S: TWritingSettings);
    function Glyph(const Character: string): TWritingGlyph;
    property FontID: string read FFontID;
    property Face: string read FFace;
    property Warnings: string read FWarnings;
  end;

implementation

uses System.Hash, System.Math, AutoWriting_Learning, AutoWriting_Inference;

constructor TWritingFontEngine.Create;
begin
  inherited; FDC:=CreateCompatibleDC(0);
  if FDC=0 then RaiseLastOSError;
  FCache:=TObjectDictionary<string,TWritingGlyph>.Create([doOwnsValues]); FRevision:=-1;
end;

destructor TWritingFontEngine.Destroy;
begin
  FCache.Free;
  if FFont<>0 then begin SelectObject(FDC,FOldFont); DeleteObject(FFont) end;
  if FDC<>0 then DeleteDC(FDC); inherited;
end;

procedure TWritingFontEngine.Configure(const S: TWritingSettings);
var Key: string; LF: TLogFont; FaceBuffer: array[0..LF_FACESIZE] of Char;
  Head,Name,Identity: TBytes; Size: Cardinal; NewFont: HFONT; Previous: HGDIOBJ; Hash: THashSHA2;
  function TableBytes(Tag: Cardinal): TBytes;
  begin
    Result:=nil; Size:=GetFontData(FDC,Tag,0,nil,0);
    if (Size=GDI_ERROR) or (Size>262144) then Exit;
    SetLength(Result,Size); if Size>0 then GetFontData(FDC,Tag,0,@Result[0],Size);
  end;
begin
  Key:=S.FontName+'|'+BoolToStr(S.Bold,True)+'|'+BoolToStr(S.Italic,True);
  if (Key=FKey) and (FRevision=LearningRevision) then Exit;
  FCache.Clear; FWarnings:=''; FRevision:=LearningRevision;
  if Key=FKey then Exit;
  FillChar(LF,SizeOf(LF),0); LF.lfHeight:=-AW_EM; LF.lfWeight:=FW_NORMAL;
  if S.Bold then LF.lfWeight:=FW_BOLD;
  LF.lfItalic:=Ord(S.Italic); LF.lfCharSet:=DEFAULT_CHARSET;
  LF.lfOutPrecision:=OUT_TT_ONLY_PRECIS; LF.lfQuality:=ANTIALIASED_QUALITY;
  StrPLCopy(LF.lfFaceName,S.FontName,LF_FACESIZE-1);
  NewFont:=CreateFontIndirect(LF); if NewFont=0 then RaiseLastOSError;
  Previous:=SelectObject(FDC,NewFont);
  try
    if GetOutlineTextMetrics(FDC,0,nil)=0 then
      raise EInvalidOp.Create('アウトラインを取得できるフォントを選んでください。');
    FillChar(FaceBuffer,SizeOf(FaceBuffer),0); GetTextFace(FDC,Length(FaceBuffer),FaceBuffer);
    Head:=TableBytes($64616568); Name:=TableBytes($656D616E);
    Identity:=TEncoding.UTF8.GetBytes(string(FaceBuffer)+'|'+BoolToStr(S.Bold,True)+'|'+BoolToStr(S.Italic,True));
    Identity:=Identity+Head+Name;
    Hash:=THashSHA2.Create; Hash.Update(Identity); FFontID:=LowerCase(Hash.HashAsString);
  except SelectObject(FDC,Previous); DeleteObject(NewFont); raise end;
  if FFont=0 then FOldFont:=Previous else DeleteObject(FFont);
  FFont:=NewFont; FFace:=FaceBuffer; FKey:=Key;
  if not SameText(FFace,S.FontName) then FWarnings:='フォント代替: '+S.FontName+' → '+FFace;
end;

function TWritingFontEngine.CreateGlyph(const Character: string): TWritingGlyph;
var Matrix: TMat2; GM: TGlyphMetrics; Bytes: TBytes; Size,Code: Cardinal;
  X,Y,Stride: Integer; Index: Word; Warning: string;
begin
  Result:=TWritingGlyph.Create;
  try
    Result.Character:=Character; Result.FontID:=FFontID; Result.FontFace:=FFace;
    FillChar(Matrix,SizeOf(Matrix),0); Matrix.eM11.Value:=1; Matrix.eM22.Value:=1;
    Code:=Ord(Character[1]); Index:=$FFFF;
    if Length(Character)=1 then GetGlyphIndicesW(FDC,PChar(Character),1,@Index,GGI_MARK_NONEXISTING_GLYPHS);
    Result.Missing:=(Index=$FFFF) and (Character<>' ') and (Character<>#9) and (Character<>'　');
    if Result.Missing then
    begin
      Code:=Ord('□');
      if Pos('未収録文字',FWarnings)=0 then FWarnings:=FWarnings+' 未収録文字は□で表示します。';
    end;
    if (Character=' ') or (Character='　') or (Character=#9) then
    begin
      Result.Advance:=AW_EM; if Character=' ' then Result.Advance:=AW_EM div 2;
      if Character=#9 then Result.Advance:=AW_EM*2; Exit;
    end;
    FillChar(GM,SizeOf(GM),0);
    Size:=GetGlyphOutlineW(FDC,Code,GGO_NATIVE,GM,0,nil,Matrix);
    if Size=GDI_ERROR then raise EInvalidOp.Create('この文字のアウトラインを取得できません: '+Character);
    Size:=GetGlyphOutlineW(FDC,Code,GGO_GRAY8_BITMAP,GM,0,nil,Matrix);
    if (Size=GDI_ERROR) or (Size>1024*1024) then raise EInvalidOp.Create('文字形状の取得に失敗しました: '+Character);
    Result.Width:=GM.gmBlackBoxX; Result.Height:=GM.gmBlackBoxY;
    Result.OriginX:=GM.gmptGlyphOrigin.X; Result.OriginY:=GM.gmptGlyphOrigin.Y;
    Result.Advance:=GM.gmCellIncX; if Result.Advance<=0 then Result.Advance:=AW_EM;
    if Size=0 then Exit;
    SetLength(Bytes,Size);
    if GetGlyphOutlineW(FDC,Code,GGO_GRAY8_BITMAP,GM,Size,@Bytes[0],Matrix)=GDI_ERROR then RaiseLastOSError;
    Stride:=(Result.Width+3) and not 3;
    if Int64(Stride)*Result.Height>Size then raise EInvalidOp.Create('Invalid glyph stride');
    SetLength(Result.Mask,Result.Width*Result.Height);
    for Y:=0 to Result.Height-1 do for X:=0 to Result.Width-1 do
      Result.Mask[Y*Result.Width+X]:=Min(255,(Integer(Bytes[Y*Stride+X])*255+32) div 64);
    // ユーザー学習を最初に検索する。自動推定・参照データから保存を作らない。
    if not LoadGlyphLearning(Result,Warning) then InferGlyphStrokes(Result);
    if Warning<>'' then FWarnings:=FWarnings+' 学習読み込み: '+Warning;
  except Result.Free; raise end;
end;

function TWritingFontEngine.Glyph(const Character: string): TWritingGlyph;
begin
  if (Character='') or (Character=#10) then raise EArgumentException.Create('Not a drawable character');
  if not FCache.TryGetValue(Character,Result) then
  begin Result:=CreateGlyph(Character); FCache.Add(Character,Result) end;
end;

end.
