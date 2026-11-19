unit AutoWriting_Types;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 設定と筆記経路の値型。元フォントのマスクはメモリーだけに保持する。

interface

uses System.SysUtils, System.Types, AviUtl2FilterTypes;

const
  AW_EM = 128;
  AW_MAX_TEXT = 4096;
  AW_MAX_PIXELS = 16777216;
  AW_VERSION = '1.0.0';

type
  // 既存4種の保存番号0..3を変えず、新しい種類を末尾に追加する。
  TPenKind = (pkPencil, pkBallpoint, pkFountain, pkBrush, pkNone, pkQuill);
  TCharacterKind = (ckKanji, ckHiragana, ckKatakana, ckNumber, ckLatin, ckSymbol);
  TWritingSettings = record
    Text, FontName: string;
    FontSize: Double;
    Bold, Italic, Vertical, ShowPen: Boolean;
    LetterGap, LineGap: Double;
    Ratios: array[TCharacterKind] of Double;
    InkColor: Cardinal;
    PenSize, PenAngle, LiftHeight, LightX, LightY: Double;
    X, Y, Scale, Transparency, Speed: Double;
    MoveSpeed: Double; // 文字間移動の px/秒。0はSpeedに連動する。
    Pen: TPenKind;
  end;
  TStroke = record
    ID: Integer;
    Reversed: Boolean;
    // 128 emマスクの左上を原点とする中心線。距離は画間移動も含め同じ単位。
    Points: TArray<TPointF>;
    // ユーザーが追加した操作点のPoints添字。自動の操作点は表示時に導出する。
    PinnedVertices: TArray<Integer>;
    StartDistance, Length: Double;
  end;
  TWritingGlyph = class
  public
    Character, FontID, FontFace: string;
    Width, Height, OriginX, OriginY, Advance: Integer;
    // この文字を持つフォントエンジンが所有する。マスク・輪郭は永続保存しない。
    Mask: TBytes;
    Reveal: TArray<Single>;
    Strokes: TArray<TStroke>;
    TotalDistance: Double;
    Learned, Missing, ReferenceUsed, ReferenceOrderOnly: Boolean;
  end;
  TWritingPixels = TArray<TPIXEL_RGBA>;

const
  AW_PEN_NAMES: array[TPenKind] of PWideChar = ('鉛筆','ボールペン','万年筆','毛筆','無し','羽ペン');
  AW_PEN_ORDER: array[0..5] of TPenKind = (pkPencil,pkBallpoint,pkFountain,pkBrush,pkQuill,pkNone);

function PenChoiceValue(Pen: TPenKind): Integer;
function PenFromChoiceValue(Value: Integer): TPenKind;
function PenChoiceIndex(Pen: TPenKind): Integer;
function DefaultWritingSettings: TWritingSettings;
function CharacterKind(const C: string): TCharacterKind;
function SettingsJSON(const S: TWritingSettings): string;
procedure ReadSettingsJSON(const JSON: string; var S: TWritingSettings);
function EncodeHostText(const Text: string): string;
function DecodeHostText(const Text: string): string;
function UnicodeCharacters(const Text: string): TArray<string>;
function Distance(const A, B: TPointF): Double;
function SafeNumber(Value, Default, MinValue, MaxValue: Double): Double;

implementation

uses System.Math, System.JSON, System.Generics.Collections, Winapi.Windows;

function PenChoiceValue(Pen: TPenKind): Integer;
begin
  // ホストが識別値順に並べても「無し」が末尾になる値とする。
  if Pen=pkNone then Result:=6 else Result:=Ord(Pen);
end;

function PenFromChoiceValue(Value: Integer): TPenKind;
begin
  case Value of
    0..3: Result:=TPenKind(Value);
    4,6: Result:=pkNone; // 直前の内部版で保存した無し4も描画時に受け付ける。
    5: Result:=pkQuill;
    else Result:=pkFountain;
  end;
end;

function PenChoiceIndex(Pen: TPenKind): Integer;
begin
  for Result:=Low(AW_PEN_ORDER) to High(AW_PEN_ORDER) do if AW_PEN_ORDER[Result]=Pen then Exit;
  Result:=2;
end;

function SafeNumber(Value, Default, MinValue, MaxValue: Double): Double;
begin
  if IsNan(Value) or IsInfinite(Value) then Value:=Default;
  Result:=EnsureRange(Value,MinValue,MaxValue);
end;

function DefaultWritingSettings: TWritingSettings;
begin
  Result:=Default(TWritingSettings);
  Result.Text:='自動筆記'+sLineBreak+'こんにちは。';
  Result.FontName:='游明朝'; Result.FontSize:=80;
  Result.ShowPen:=True; Result.LetterGap:=0.08; Result.LineGap:=0.4;
  Result.Ratios[ckKanji]:=1; Result.Ratios[ckHiragana]:=0.9;
  Result.Ratios[ckKatakana]:=0.95; Result.Ratios[ckNumber]:=0.9;
  Result.Ratios[ckLatin]:=1; Result.Ratios[ckSymbol]:=1;
  Result.InkColor:=$FFFFFF; Result.PenSize:=1; Result.PenAngle:=35;
  Result.LiftHeight:=16; Result.LightX:=-100; Result.LightY:=-100; Result.Scale:=100; Result.Speed:=240;
  Result.Pen:=pkFountain;
end;

function CharacterKind(const C: string): TCharacterKind;
var U: Cardinal;
begin
  if C='' then Exit(ckSymbol);
  U:=Ord(C[1]);
  if (U>=$D800) and (U<=$DBFF) and (Length(C)=2) then
    U:=$10000+(U-$D800)*1024+Ord(C[2])-$DC00;
  if ((U>=$3400) and (U<=$9FFF)) or ((U>=$F900) and (U<=$FAFF)) or
     ((U>=$20000) and (U<=$323AF)) then Exit(ckKanji);
  if (U>=$3040) and (U<=$309F) then Exit(ckHiragana);
  if ((U>=$30A0) and (U<=$30FF)) or ((U>=$FF65) and (U<=$FF9F)) then Exit(ckKatakana);
  if ((U>=Ord('0')) and (U<=Ord('9'))) or ((U>=$FF10) and (U<=$FF19)) then Exit(ckNumber);
  if ((U>=65) and (U<=90)) or ((U>=97) and (U<=122)) or
     ((U>=$FF21) and (U<=$FF5A)) then Exit(ckLatin);
  Result:=ckSymbol;
end;

function SettingsJSON(const S: TWritingSettings): string;
var J: TJSONObject; A: TJSONArray; K: TCharacterKind;
begin
  J:=TJSONObject.Create;
  try
    J.AddPair('schema',TJSONNumber.Create(1)); J.AddPair('font',S.FontName);
    J.AddPair('size',TJSONNumber.Create(S.FontSize));
    J.AddPair('bold',TJSONBool.Create(S.Bold)); J.AddPair('italic',TJSONBool.Create(S.Italic));
    J.AddPair('vertical',TJSONBool.Create(S.Vertical)); J.AddPair('showPen',TJSONBool.Create(S.ShowPen));
    J.AddPair('letterGap',TJSONNumber.Create(S.LetterGap)); J.AddPair('lineGap',TJSONNumber.Create(S.LineGap));
    J.AddPair('ink',TJSONNumber.Create(Int64(S.InkColor)));
    J.AddPair('penSize',TJSONNumber.Create(S.PenSize)); J.AddPair('penAngle',TJSONNumber.Create(S.PenAngle));
    J.AddPair('lift',TJSONNumber.Create(S.LiftHeight));
    J.AddPair('lightX',TJSONNumber.Create(S.LightX)); J.AddPair('lightY',TJSONNumber.Create(S.LightY)); A:=TJSONArray.Create;
    for K:=Low(K) to High(K) do A.Add(S.Ratios[K]);
    J.AddPair('ratios',A); Result:=J.ToJSON;
  finally J.Free end;
end;

procedure ReadSettingsJSON(const JSON: string; var S: TWritingSettings);
var V: TJSONValue; J: TJSONObject; A: TJSONArray; K: TCharacterKind;
  function Num(const Name: string; D,Lo,Hi: Double): Double;
  begin Result:=SafeNumber(J.GetValue<Double>(Name,D),D,Lo,Hi) end;
begin
  if (JSON='') or (Length(JSON)>32768) then Exit;
  V:=TJSONObject.ParseJSONValue(JSON);
  try
    try
    if not (V is TJSONObject) then Exit;
    J:=TJSONObject(V); if J.GetValue<Integer>('schema',0)<>1 then Exit;
    S.FontName:=Copy(J.GetValue<string>('font',S.FontName),1,LF_FACESIZE-1);
    S.FontSize:=Num('size',S.FontSize,12,256);
    S.Bold:=J.GetValue<Boolean>('bold',S.Bold); S.Italic:=J.GetValue<Boolean>('italic',S.Italic);
    S.Vertical:=J.GetValue<Boolean>('vertical',S.Vertical); S.ShowPen:=J.GetValue<Boolean>('showPen',S.ShowPen);
    S.LetterGap:=Num('letterGap',S.LetterGap,-0.5,3); S.LineGap:=Num('lineGap',S.LineGap,0,4);
    S.InkColor:=Round(Num('ink',S.InkColor,0,$FFFFFF));
    S.PenSize:=Num('penSize',S.PenSize,0.3,3); S.PenAngle:=Num('penAngle',S.PenAngle,-180,180);
    S.LiftHeight:=Num('lift',S.LiftHeight,0,80);
    S.LightX:=Num('lightX',S.LightX,-400,400); S.LightY:=Num('lightY',S.LightY,-400,400);
    A:=J.GetValue<TJSONArray>('ratios');
    if (A<>nil) and (A.Count=6) then
      for K:=Low(K) to High(K) do S.Ratios[K]:=SafeNumber(A.Items[Ord(K)].AsType<Double>,S.Ratios[K],0.3,2);
    except
    // 未知・破損した設定からDLL境界へ例外を漏らさず、読めた値と初期値を使う。
    end;
  finally V.Free end;
end;

function EncodeHostText(const Text: string): string;
begin
  Result:=StringReplace(Text,'\','\\',[rfReplaceAll]);
  Result:=StringReplace(Result,#13#10,#10,[rfReplaceAll]);
  Result:=StringReplace(Result,#13,#10,[rfReplaceAll]);
  Result:=StringReplace(Result,#10,'\n',[rfReplaceAll]);
end;

function DecodeHostText(const Text: string): string;
var I: Integer;
begin
  Result:=''; I:=1;
  while (I<=Length(Text)) and (Length(Result)<AW_MAX_TEXT) do
  begin
    if (Text[I]='\') and (I<Length(Text)) then
      if Text[I+1]='n' then begin Result:=Result+sLineBreak; Inc(I,2); Continue end
      else if Text[I+1]='\' then begin Result:=Result+'\'; Inc(I,2); Continue end;
    Result:=Result+Text[I]; Inc(I);
  end;
end;

function UnicodeCharacters(const Text: string): TArray<string>;
var L: TList<string>; I: Integer; C: string;
begin
  L:=TList<string>.Create;
  try
    I:=1;
    while I<=Min(Length(Text),AW_MAX_TEXT) do
    begin
      C:=Text[I];
      if (Text[I]=#13) and (I<Length(Text)) and (Text[I+1]=#10) then Inc(I)
      else if (Ord(Text[I])>=$D800) and (Ord(Text[I])<=$DBFF) and (I<Length(Text)) and
        (Ord(Text[I+1])>=$DC00) and (Ord(Text[I+1])<=$DFFF) then
        begin Inc(I); C:=C+Text[I] end;
      if C=#13 then C:=#10;
      L.Add(C); Inc(I);
    end;
    Result:=L.ToArray;
  finally L.Free end;
end;

function Distance(const A,B: TPointF): Double;
begin Result:=Hypot(A.X-B.X,A.Y-B.Y) end;

end.
