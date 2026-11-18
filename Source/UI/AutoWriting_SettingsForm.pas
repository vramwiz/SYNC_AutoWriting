unit AutoWriting_SettingsForm;

// Copyright (c) 2026 VRAMの魔術師
// SPDX-License-Identifier: GPL-3.0-only
// 独自プレビューと3ペイン筆順編集。ホスト映像やホスト所有ポインターを参照しない。
// フォームと全VCL子コントロールはモーダル呼出し内で作成・破棄する。

interface

uses AutoWriting_Types;

// 閉じる時に検証しSettingsへ編集結果を返す。学習操作は編集時に独立して保存する。
function EditWritingSettings(var Settings: TWritingSettings): Boolean;

implementation

uses Winapi.Windows, Winapi.Messages, System.SysUtils, System.Classes, System.Types, System.Math, System.UITypes,
  System.Generics.Collections,
  Vcl.Forms, Vcl.Controls, Vcl.StdCtrls, Vcl.ExtCtrls, Vcl.ComCtrls,
  Vcl.Graphics, Vcl.Dialogs, Vcl.Samples.Spin, Vcl.Menus, Vcl.ImgList, Vcl.NumberBox, AutoWriting_Fonts,
  AutoWriting_Renderer, AutoWriting_Inference, AutoWriting_Learning, AutoWriting_Editing, AutoWriting_Vertices;

type
  TWritingStrokeListBox = class(TListBox)
  private
    FDropIndex: Integer;
    procedure SetDropIndex(Value: Integer);
    procedure PaintDropLine(DC: HDC);
    procedure WMPaint(var Message: TWMPaint); message WM_PAINT;
    procedure WMPrintClient(var Message: TWMPrintClient); message WM_PRINTCLIENT;
  public
    constructor Create(AOwner: TComponent); override;
    property DropIndex: Integer read FDropIndex write SetDropIndex;
  end;
  // 親タブの背景消去から独立した不透明描画面。次のフレームが完成するまで前回を保つ。
  TWritingPaintBox = class(TCustomControl)
  private
    FOnPaint: TNotifyEvent;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    property Canvas;
    property MouseCapture;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnContextPopup;
  end;
  TWritingSettingsForm = class(TForm)
  private
    FSettings: TWritingSettings;
    FPreview,FSingle: TWritingRenderer;
    FPreviewPixels,FSinglePixels: TWritingPixels;
    FDisplayBitmap: TBitmap;
    FEditEngine: TWritingFontEngine;
    FCurrent: TWritingGlyph;
    FPages: TPageControl;
    FPreviewPage,FEditPage: TTabSheet;
    FPreviewPaint,FEditPaint: TWritingPaintBox;
    FMemo: TMemo;
    FFontButton,FColorButton: TButton;
    FPen,FDirection: TComboBox;
    FShowPen: TCheckBox;
    FSize,FSpeed,FLetter,FLine,FAngle,FLift,FLightX,FLightY: TSpinEdit;
    FPenSize: TNumberBox;
    FRatios: array[TCharacterKind] of TSpinEdit;
    FChars: TListBox;
    FStrokes: TWritingStrokeListBox;
    FStatus,FTimeLabel,FEditorStatus: TLabel;
    FTimer: TTimer;
    FStart,FPausedAt,FChangedAt,FSingleStart: UInt64;
    FPaused,FUpdating,FDirty,FSinglePlaying,FSpeedChanged,FAngleChanged,FPathChanged: Boolean;
    FLightXChanged,FLightYChanged,FPenSizeChanged: Boolean;
    FDragPoint,FSelectedPoint: Integer;
    FDragIndices: TArray<Integer>;
    FViewScale,FViewX,FViewY: Double;
    FSelectedHit: TStrokeHit;
    FEditorMenu,FStrokeMenu,FPointMenu: TPopupMenu;
    FChoosePointItem: TMenuItem;
    FPointIcons: TImageList;
    FPointHits: TArray<TStrokeHit>;
    FPointIndices: TArray<Integer>;
    FVertices: TArray<TArray<Integer>>;
    FDragOrigin: TPoint;
    FDragBefore: TGlyphEditState;
    FUndo,FRedo: TList<TGlyphEditState>;
    FHistoryKey: string;
    procedure Changed(Sender: TObject);
    procedure Tick(Sender: TObject);
    procedure PaintPreview(Sender: TObject);
    procedure PaintEditor(Sender: TObject);
    procedure SelectCharacter(Sender: TObject);
    procedure SelectStroke(Sender: TObject);
    procedure PickFont(Sender: TObject);
    procedure PickColor(Sender: TObject);
    procedure FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure MenuAction(Sender: TObject);
    procedure MenuPopup(Sender: TObject);
    procedure PointChoice(Sender: TObject);
    procedure PathContext(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure StrokeContext(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure CreateEditorMenus;
    procedure SelectPathPoint(const Hit: TStrokeHit; PointIndex: Integer);
    procedure GatherPointChoices(X,Y: Integer);
    procedure PopulatePointChoices(ParentItem: TMenuItem);
    function SelectedStrokes: TArray<Integer>;
    procedure SetStrokeSelection(const Indices: TArray<Integer>);
    function CanEditAction(Action: Integer): Boolean;
    procedure ExecuteEditAction(Action: Integer);
    procedure StrokeDragOver(Sender,Source: TObject; X,Y: Integer; State: TDragState; var Accept: Boolean);
    procedure StrokeDragDrop(Sender,Source: TObject; X,Y: Integer);
    procedure StrokeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure StrokeStartDrag(Sender: TObject; var DragObject: TDragObject);
    procedure StrokeEndDrag(Sender,Target: TObject; X,Y: Integer);
    procedure PathMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure PathMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
    procedure PathMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure DrawCharacter(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure DrawStroke(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
    procedure CloseSettings(Sender: TObject; var CanClose: Boolean);
    procedure PageChanged(Sender: TObject);
    procedure RestartClick(Sender: TObject);
    procedure ReadControls;
    procedure Rebuild;
    procedure UpdateStrokeList;
    procedure PersistCurrent;
    procedure UpdateEditorStatus;
    procedure CommitEdit(const Before: TGlyphEditState; Save: Boolean=True);
    procedure ApplyHistory(Redo: Boolean);
    procedure DrawPixels(Canvas: TCanvas; const Rect: TRect; const Pixels: TWritingPixels; W,H: Integer);
    function AddSpin(Parent: TWinControl; const Caption: string; Y,Value,Min,Max: Integer): TSpinEdit;
    function AddButton(Parent: TWinControl; const Caption: string; X,Y,W: Integer; Event: TNotifyEvent): TButton;
  public
    constructor CreateForSettings(const S: TWritingSettings);
    destructor Destroy; override;
  end;

const
  KIND_NAMES: array[TCharacterKind] of string = ('漢字','ひらがな','カタカナ','数字','英字','記号');
  STROKE_COLORS: array[0..9] of TColor = ($4848D6,$CE8742,$74A153,$B667B1,$C2B13C,$6796E2,$C3765C,$9B69CB,$419CA2,$82954C);
  EA_SPLIT=1; EA_JOIN=2; EA_REVERSE=3; EA_UP=4; EA_DOWN=5;
  EA_UNDO=6; EA_REDO=7; EA_RESET=8; EA_PLAY=9; EA_SELECTALL=10; EA_REVERSEPOINT=11; EA_VERTEX=12;

constructor TWritingStrokeListBox.Create(AOwner: TComponent);
begin inherited; FDropIndex:=-1 end;

procedure TWritingStrokeListBox.SetDropIndex(Value: Integer);
begin if Value<>FDropIndex then begin FDropIndex:=Value; Invalidate end end;

procedure TWritingStrokeListBox.PaintDropLine(DC: HDC);
var OwnDC: Boolean; C: TCanvas; R: TRect; Y: Integer;
begin
  if (FDropIndex<0) or (Items.Count=0) then Exit;
  OwnDC:=DC=0; if OwnDC then DC:=GetDC(Handle);
  C:=TCanvas.Create;
  try
    C.Handle:=DC; R:=ItemRect(Min(FDropIndex,Items.Count-1)); Y:=R.Top;
    if FDropIndex=Items.Count then Y:=R.Bottom-2;
    Y:=EnsureRange(Y,1,Max(1,ClientHeight-2));
    C.Pen.Color:=$D06518; C.Pen.Width:=3; C.MoveTo(2,Y); C.LineTo(ClientWidth-2,Y);
    C.Brush.Color:=$D06518; C.Polygon([Point(2,Y-5),Point(8,Y),Point(2,Y+5)]);
    C.Polygon([Point(ClientWidth-3,Y-5),Point(ClientWidth-9,Y),Point(ClientWidth-3,Y+5)]);
  finally C.Handle:=0; C.Free; if OwnDC then ReleaseDC(Handle,DC) end;
end;

procedure TWritingStrokeListBox.WMPaint(var Message: TWMPaint);
begin inherited; PaintDropLine(Message.DC) end;

procedure TWritingStrokeListBox.WMPrintClient(var Message: TWMPrintClient);
begin inherited; PaintDropLine(Message.DC) end;

constructor TWritingPaintBox.Create(AOwner: TComponent);
begin
  inherited;
  ControlStyle:=(ControlStyle+[csOpaque])-[csParentBackground];
  ParentDoubleBuffered:=False; DoubleBuffered:=True; DoubleBufferedMode:=dbmRequested;
end;

procedure TWritingPaintBox.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  // フレーム全体はPaintが描く。WM_PAINTより先に画面を空白にしない。
  Message.Result:=1;
end;

procedure TWritingPaintBox.Paint;
begin
  Canvas.Font:=Font; Canvas.Brush.Color:=Color;
  if Assigned(FOnPaint) then FOnPaint(Self) else Canvas.FillRect(ClientRect);
end;

function TWritingSettingsForm.AddSpin(Parent: TWinControl; const Caption: string; Y,Value,Min,Max: Integer): TSpinEdit;
var L: TLabel;
begin
  L:=TLabel.Create(Self); L.Parent:=Parent; L.SetBounds(12,Y+5,204,22); L.Caption:=Caption;
  Result:=TSpinEdit.Create(Self); Result.Parent:=Parent; Result.SetBounds(232,Y,84,27);
  Result.MinValue:=Min; Result.MaxValue:=Max; Result.Value:=Value; Result.OnChange:=Changed;
end;

function TWritingSettingsForm.AddButton(Parent: TWinControl; const Caption: string; X,Y,W: Integer; Event: TNotifyEvent): TButton;
begin
  Result:=TButton.Create(Self); Result.Parent:=Parent; Result.SetBounds(X,Y,W,30);
  Result.Caption:=Caption; Result.OnClick:=Event;
end;

procedure TWritingSettingsForm.CreateEditorMenus;
var Bitmap: TBitmap; I: Integer;
  function AddAction(Menu: TPopupMenu; const Text: string; Action: Integer; Key: Word; Shift: TShiftState): TMenuItem;
  begin
    Result:=TMenuItem.Create(Self); Result.Caption:=Text; Result.Tag:=Action;
    if Key<>0 then Result.ShortCut:=ShortCut(Key,Shift);
    Result.OnClick:=MenuAction; Menu.Items.Add(Result);
  end;
  procedure CommonActions(Menu: TPopupMenu);
  begin
    AddAction(Menu,'選択した画を結合',EA_JOIN,Ord('J'),[ssCtrl]);
    if Menu<>FEditorMenu then AddAction(Menu,'描画方向を反転',EA_REVERSE,Ord('R'),[ssCtrl]);
    AddAction(Menu,'上へ移動',EA_UP,VK_UP,[ssAlt]); AddAction(Menu,'下へ移動',EA_DOWN,VK_DOWN,[ssAlt]);
    AddAction(Menu,'-',0,0,[]);
    AddAction(Menu,'元に戻す',EA_UNDO,Ord('Z'),[ssCtrl]); AddAction(Menu,'やり直す',EA_REDO,Ord('Y'),[ssCtrl]);
    AddAction(Menu,'自動推定に戻す',EA_RESET,Ord('R'),[ssCtrl,ssShift]);
    AddAction(Menu,'-',0,0,[]);
    AddAction(Menu,'すべての画を選択',EA_SELECTALL,Ord('A'),[ssCtrl]);
    AddAction(Menu,'1文字を再生／停止',EA_PLAY,VK_SPACE,[]);
    Menu.OnPopup:=MenuPopup;
  end;
begin
  FPointIcons:=TImageList.Create(Self); FPointIcons.Width:=22; FPointIcons.Height:=22;
  Bitmap:=TBitmap.Create;
  try
    Bitmap.SetSize(22,22);
    for I:=0 to High(STROKE_COLORS) do
    begin
      Bitmap.Canvas.Brush.Color:=clFuchsia; Bitmap.Canvas.FillRect(Rect(0,0,22,22));
      Bitmap.Canvas.Pen.Color:=clWhite; Bitmap.Canvas.Pen.Width:=2;
      Bitmap.Canvas.Brush.Color:=STROKE_COLORS[I]; Bitmap.Canvas.Ellipse(2,2,21,21);
      FPointIcons.AddMasked(Bitmap,clFuchsia);
    end;
  finally Bitmap.Free end;
  FEditorMenu:=TPopupMenu.Create(Self); FEditorMenu.Images:=FPointIcons;
  AddAction(FEditorMenu,'ここで分割',EA_SPLIT,Ord('K'),[ssCtrl]);
  AddAction(FEditorMenu,'この画の描画方向を反転',EA_REVERSEPOINT,Ord('R'),[ssCtrl]);
  AddAction(FEditorMenu,'頂点を作成',EA_VERTEX,Ord('I'),[ssCtrl]);
  FChoosePointItem:=AddAction(FEditorMenu,'重なる点・線を選び直す',0,0,[]);
  AddAction(FEditorMenu,'-',0,0,[]); CommonActions(FEditorMenu);
  FStrokeMenu:=TPopupMenu.Create(Self); CommonActions(FStrokeMenu);
  FPointMenu:=TPopupMenu.Create(Self); FPointMenu.Images:=FPointIcons;
end;

function TWritingSettingsForm.SelectedStrokes: TArray<Integer>;
var I,N: Integer;
begin
  SetLength(Result,FStrokes.SelCount); N:=0;
  for I:=0 to FStrokes.Count-1 do if FStrokes.Selected[I] then begin Result[N]:=I; Inc(N) end;
end;

procedure TWritingSettingsForm.SetStrokeSelection(const Indices: TArray<Integer>);
var I: Integer;
begin
  FStrokes.ClearSelection;
  for I in Indices do if (I>=0) and (I<FStrokes.Count) then FStrokes.Selected[I]:=True;
  if Length(Indices)>0 then SendMessage(FStrokes.Handle,LB_SETCARETINDEX,Indices[0],0);
end;

procedure TWritingSettingsForm.SelectPathPoint(const Hit: TStrokeHit; PointIndex: Integer);
begin
  FSelectedHit:=Hit; FSelectedPoint:=PointIndex; FSinglePlaying:=False;
  SetStrokeSelection([Hit.Stroke]); UpdateEditorStatus; FEditPaint.Invalidate;
end;

procedure TWritingSettingsForm.GatherPointChoices(X,Y: Integer);
begin
  FPointHits:=nil; FPointIndices:=nil; if (FCurrent=nil) or (FViewScale<=0) then Exit;
  FPointHits:=HitEditingPaths(FCurrent,PointF((X-FViewX)/FViewScale,(Y-FViewY)/FViewScale),
    12/FViewScale,14/FViewScale,FPointIndices);
end;
procedure TWritingSettingsForm.PopulatePointChoices(ParentItem: TMenuItem);
var I,J,Number: Integer; Item: TMenuItem; Progress: Double;
begin
  ParentItem.Clear;
  for I:=0 to High(FPointHits) do
  begin
    Item:=TMenuItem.Create(Self);
    if FPointIndices[I]>=0 then
    begin
      Number:=1;
      for J:=0 to High(FVertices[FPointHits[I].Stroke]) do
        if FVertices[FPointHits[I].Stroke][J]=FPointIndices[I] then begin Number:=J+1; Break end;
      Item.Caption:=Format('%d画目・頂点%d',[FPointHits[I].Stroke+1,Number]);
    end
    else begin
      Progress:=0;
      with FCurrent.Strokes[FPointHits[I].Stroke] do
      begin
        for J:=1 to FPointHits[I].Segment do Progress:=Progress+Distance(Points[J-1],Points[J]);
        Progress:=(Progress+Distance(Points[FPointHits[I].Segment],FPointHits[I].Point))/Max(1,Length);
      end;
      Item.Caption:=Format('%d画目・線上（%d%%）',[FPointHits[I].Stroke+1,EnsureRange(Round(Progress*100),0,100)]);
    end;
    Item.Tag:=I; Item.ImageIndex:=FPointHits[I].Stroke mod Length(STROKE_COLORS);
    Item.OnClick:=PointChoice; ParentItem.Add(Item);
  end;
end;

procedure TWritingSettingsForm.PointChoice(Sender: TObject);
var I: Integer;
begin
  I:=TMenuItem(Sender).Tag;
  if (I>=0) and (I<Length(FPointHits)) then SelectPathPoint(FPointHits[I],FPointIndices[I]);
end;

procedure TWritingSettingsForm.PathContext(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var P: TPoint; I,Choice: Integer;
begin
  Handled:=True; FSinglePlaying:=False; FDragPoint:=-1; FEditPaint.MouseCapture:=False;
  FEditPaint.SetFocus;
  if (MousePos.X<0) and (FSelectedHit.Stroke>=0) then
    MousePos:=Point(Round(FViewX+FSelectedHit.Point.X*FViewScale),Round(FViewY+FSelectedHit.Point.Y*FViewScale));
  if MousePos.X<0 then MousePos:=Point(20,20);
  if (FSelectedHit.Stroke<0) or
    (Hypot(FViewX+FSelectedHit.Point.X*FViewScale-MousePos.X,FViewY+FSelectedHit.Point.Y*FViewScale-MousePos.Y)>10) then
  begin
    GatherPointChoices(MousePos.X,MousePos.Y);
    Choice:=-1; if Length(FPointHits)=1 then Choice:=0;
    for I:=0 to High(FPointHits) do if FPointHits[I].Stroke=FStrokes.ItemIndex then begin Choice:=I; Break end;
    if Choice>=0 then SelectPathPoint(FPointHits[Choice],FPointIndices[Choice])
    else begin FSelectedHit.Stroke:=-1; FSelectedPoint:=-1; UpdateEditorStatus; FEditPaint.Invalidate end;
  end;
  if FSelectedHit.Stroke>=0 then
    GatherPointChoices(Round(FViewX+FSelectedHit.Point.X*FViewScale),Round(FViewY+FSelectedHit.Point.Y*FViewScale))
  else GatherPointChoices(MousePos.X,MousePos.Y);
  PopulatePointChoices(FChoosePointItem); FChoosePointItem.Enabled:=Length(FPointHits)>1;
  P:=FEditPaint.ClientToScreen(MousePos); FEditorMenu.Popup(P.X,P.Y);
end;

procedure TWritingSettingsForm.StrokeContext(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
var P: TPoint;
begin
  Handled:=True; if MousePos.X<0 then MousePos:=Point(20,20);
  FStrokes.SetFocus;
  P:=FStrokes.ClientToScreen(MousePos); FStrokeMenu.Popup(P.X,P.Y);
end;

function TWritingSettingsForm.CanEditAction(Action: Integer): Boolean;
var H: TStrokeHit;
begin
  Result:=False;
  if (FCurrent=nil) or (FPages.ActivePage<>FEditPage) or (ActiveControl is TCustomEdit) then Exit;
  case Action of
    EA_SPLIT: begin
      H:=FSelectedHit;
      Result:=(H.Stroke>=0) and (H.Stroke<Length(FCurrent.Strokes)); if not Result then Exit;
      Result:=(H.Segment>=0) and (H.Segment<High(FCurrent.Strokes[H.Stroke].Points)) and
        not ((H.Segment=0) and (H.T<=0.001)) and
        not ((H.Segment=High(FCurrent.Strokes[H.Stroke].Points)-1) and (H.T>=0.999));
    end;
    EA_JOIN: Result:=FStrokes.SelCount>=2;
    EA_REVERSE,EA_UP,EA_DOWN: Result:=FStrokes.SelCount>0;
    EA_REVERSEPOINT: Result:=(FSelectedHit.Stroke>=0) and (FSelectedHit.Stroke<Length(FCurrent.Strokes));
    EA_VERTEX: Result:=(FSelectedHit.Stroke>=0) and (FSelectedPoint<0);
    EA_UNDO: Result:=FUndo.Count>0;
    EA_REDO: Result:=FRedo.Count>0;
    EA_RESET,EA_PLAY,EA_SELECTALL: Result:=True;
  end;
end;

procedure TWritingSettingsForm.MenuPopup(Sender: TObject);
var Menu: TPopupMenu; I: Integer;
begin
  Menu:=TPopupMenu(Sender);
  for I:=0 to Menu.Items.Count-1 do if Menu.Items[I].Tag<>0 then
    Menu.Items[I].Enabled:=CanEditAction(Menu.Items[I].Tag);
end;

procedure TWritingSettingsForm.MenuAction(Sender: TObject);
begin ExecuteEditAction(TMenuItem(Sender).Tag) end;

procedure TWritingSettingsForm.ExecuteEditAction(Action: Integer);
var Before: TGlyphEditState; Indices,After: TArray<Integer>; I,Index,KeepPoint: Integer; KeepHit: TStrokeHit;
begin
  if not CanEditAction(Action) then Exit;
  if Action=EA_UNDO then begin ApplyHistory(False); Exit end;
  if Action=EA_REDO then begin ApplyHistory(True); Exit end;
  if Action=EA_PLAY then
  begin FSinglePlaying:=not FSinglePlaying; FSingleStart:=GetTickCount64; FEditPaint.Invalidate; Exit end;
  if Action=EA_SELECTALL then begin FStrokes.SelectAll; SelectStroke(nil); Exit end;
  Indices:=SelectedStrokes;
  if Action=EA_REVERSEPOINT then begin Indices:=[FSelectedHit.Stroke]; Action:=EA_REVERSE end;
  KeepHit:=FSelectedHit; KeepPoint:=FSelectedPoint;
  Before:=CaptureGlyphState(FCurrent); FSinglePlaying:=False;
  case Action of
    EA_VERTEX: begin
      if not CreateStrokeVertex(FCurrent,FSelectedHit,KeepPoint) then Exit;
      KeepHit:=FSelectedHit; KeepHit.Point:=FCurrent.Strokes[KeepHit.Stroke].Points[KeepPoint];
      KeepHit.Segment:=Max(0,KeepPoint-1); KeepHit.T:=1; if KeepPoint=0 then KeepHit.T:=0;
      After:=[KeepHit.Stroke];
    end;
    EA_SPLIT: begin
      Index:=FSelectedHit.Stroke;
      if not SplitStrokeAt(FCurrent,FSelectedHit) then Exit;
      After:=[Index,Index+1];
    end;
    EA_JOIN: begin
      if not JoinSelectedStrokes(FCurrent,Indices,Index) then Exit;
      After:=[Index];
    end;
    EA_REVERSE: begin
      for I in Indices do ReverseGlyphStroke(FCurrent,I); After:=Indices;
      if (Length(Indices)=1) and (KeepHit.Stroke=Indices[0]) then
      begin
        Index:=High(FCurrent.Strokes[KeepHit.Stroke].Points);
        KeepHit.Segment:=Index-1-KeepHit.Segment; KeepHit.T:=1-KeepHit.T;
        if KeepPoint>=0 then KeepPoint:=Index-KeepPoint;
      end else KeepHit.Stroke:=-1;
    end;
    EA_UP,EA_DOWN: begin
      Index:=-1; if Action=EA_DOWN then Index:=1;
      if not ShiftSelectedStrokes(FCurrent,Indices,Index,After) then Exit;
    end;
    EA_RESET: begin
      try DeleteGlyphLearning(FCurrent); CommitEdit(Before,False)
      except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0) end;
      Exit;
    end;
    else Exit;
  end;
  CommitEdit(Before); SetStrokeSelection(After); UpdateEditorStatus; FEditPaint.Invalidate;
  if (Action in [EA_REVERSE,EA_VERTEX]) and (KeepHit.Stroke>=0) then SelectPathPoint(KeepHit,KeepPoint);
end;

constructor TWritingSettingsForm.CreateForSettings(const S: TWritingSettings);
var Bottom,LeftPanel,RightPanel,HelpPanel: TPanel; Scroll: TScrollBox;
  L: TLabel; B: TButton; K: TCharacterKind; P: TPenKind; Y: Integer;
begin
  inherited CreateNew(nil); FSettings:=S; FUpdating:=True;
  Caption:='自動筆記 — SYNC_AutoWriting v'+AW_VERSION;
  Position:=poScreenCenter; ClientWidth:=1120; ClientHeight:=790;
  Constraints.MinWidth:=940; Constraints.MinHeight:=700;
  Font.Name:='Yu Gothic UI'; Font.Size:=10; KeyPreview:=True; OnKeyDown:=FormKey;
  OnCloseQuery:=CloseSettings;
  FDragPoint:=-1; FSelectedPoint:=-1; FSelectedHit.Stroke:=-1;
  FPreview:=TWritingRenderer.Create; FSingle:=TWritingRenderer.Create; FEditEngine:=TWritingFontEngine.Create;
  FUndo:=TList<TGlyphEditState>.Create; FRedo:=TList<TGlyphEditState>.Create;
  FDisplayBitmap:=TBitmap.Create; FDisplayBitmap.PixelFormat:=pf32bit;
  Bottom:=TPanel.Create(Self); Bottom.Parent:=Self; Bottom.Align:=alBottom; Bottom.Height:=29; Bottom.BevelOuter:=bvNone;
  FStatus:=TLabel.Create(Self); FStatus.Parent:=Bottom; FStatus.AutoSize:=False;
  FStatus.SetBounds(12,5,ClientWidth-24,22); FStatus.Anchors:=[akLeft,akTop,akRight]; FStatus.ShowHint:=True;
  FStatus.Caption:='閉じると文章・設定を反映します。Space: 一時停止 / 再開';
  FPages:=TPageControl.Create(Self); FPages.Parent:=Self; FPages.Align:=alClient; FPages.OnChange:=PageChanged;
  FPreviewPage:=TTabSheet.Create(Self); FPreviewPage.PageControl:=FPages; FPreviewPage.Caption:='プレビュー';
  FEditPage:=TTabSheet.Create(Self); FEditPage.PageControl:=FPages; FEditPage.Caption:='書き順編集';
  Scroll:=TScrollBox.Create(Self); Scroll.Parent:=FPreviewPage; Scroll.Align:=alLeft; Scroll.Width:=340;
  Scroll.HorzScrollBar.Visible:=False; Scroll.BorderStyle:=bsNone;
  L:=TLabel.Create(Self); L.Parent:=Scroll; L.SetBounds(12,10,300,23); L.Caption:='表示文字列（改行できます）';
  FMemo:=TMemo.Create(Self); FMemo.Parent:=Scroll; FMemo.SetBounds(12,36,304,116);
  FMemo.ScrollBars:=ssVertical; FMemo.MaxLength:=AW_MAX_TEXT; FMemo.Text:=S.Text; FMemo.OnChange:=Changed;
  FFontButton:=AddButton(Scroll,S.FontName,12,162,304,PickFont);
  FSize:=AddSpin(Scroll,'基準文字サイズ',202,Round(S.FontSize),12,256);
  L:=TLabel.Create(Self); L.Parent:=Scroll; L.SetBounds(12,241,204,22); L.Caption:='ペンサイズ（%）';
  FPenSize:=TNumberBox.Create(Self); FPenSize.Parent:=Scroll; FPenSize.SetBounds(216,236,100,27);
  FPenSize.Mode:=nbmFloat; FPenSize.Decimal:=2; FPenSize.MinValue:=30; FPenSize.MaxValue:=300;
  FPenSize.SmallStep:=0.01; FPenSize.LargeStep:=1; FPenSize.Value:=S.PenSize*100; FPenSize.OnChangeValue:=Changed;
  FPenSize.ShowHint:=True; FPenSize.Hint:='100で標準、0.01刻み。AviUtl2側の「ペンサイズ」と共通です。';
  FSpeed:=AddSpin(Scroll,'ペン速度（px / 秒）',270,Round(S.Speed),1,10000);
  L:=TLabel.Create(Self); L.Parent:=Scroll; L.SetBounds(12,309,150,22); L.Caption:='筆記具';
  FPen:=TComboBox.Create(Self); FPen.Parent:=Scroll; FPen.SetBounds(142,306,174,27); FPen.Style:=csDropDownList; FPen.Sorted:=False;
  for P in AW_PEN_ORDER do FPen.Items.Add(string(AW_PEN_NAMES[P]));
  FPen.ItemIndex:=PenChoiceIndex(S.Pen); FPen.OnChange:=Changed;
  FShowPen:=TCheckBox.Create(Self); FShowPen.Parent:=Scroll; FShowPen.SetBounds(12,341,300,25);
  FShowPen.Caption:='ペン・筆を表示'; FShowPen.Checked:=S.ShowPen; FShowPen.OnClick:=Changed;
  FColorButton:=AddButton(Scroll,'文字色を選択',12,373,304,PickColor);
  L:=TLabel.Create(Self); L.Parent:=Scroll; L.SetBounds(12,417,130,22); L.Caption:='文字の向き';
  FDirection:=TComboBox.Create(Self); FDirection.Parent:=Scroll; FDirection.SetBounds(142,412,174,27);
  FDirection.Style:=csDropDownList; FDirection.Items.AddStrings(['横書き','縦書き']); FDirection.ItemIndex:=Ord(S.Vertical); FDirection.OnChange:=Changed;
  FLetter:=AddSpin(Scroll,'字間（基準サイズの %）',451,Round(S.LetterGap*100),-50,300);
  FLine:=AddSpin(Scroll,'行の追加間隔（%）',485,Round(S.LineGap*100),0,400);
  L:=TLabel.Create(Self); L.Parent:=Scroll; L.SetBounds(12,526,300,22); L.Caption:='文字種別のサイズ比率';
  Y:=556;
  for K:=Low(K) to High(K) do
  begin FRatios[K]:=AddSpin(Scroll,KIND_NAMES[K]+'（%）',Y,Round(S.Ratios[K]*100),30,200); Inc(Y,34) end;
  FAngle:=AddSpin(Scroll,'ペン角度（0°＝上）',Y+12,Round(S.PenAngle),-180,180);
  FAngle.ShowHint:=True; FAngle.Hint:='正の値で右、負の値で左へ傾きます。AviUtl2側の「ペン角度」と共通です。';
  FLift:=AddSpin(Scroll,'ペンを上げる高さ',Y+46,Round(S.LiftHeight),0,80);
  FLightX:=AddSpin(Scroll,'光源X（左− / 右＋）',Y+80,Round(S.LightX),-400,400);
  FLightY:=AddSpin(Scroll,'光源Y（上− / 下＋）',Y+114,Round(S.LightY),-400,400);
  FLightX.ShowHint:=True; FLightX.Hint:='ペン先を基準にした光源方向。左から照らすと影が右へ伸びます。AviUtl2側と共通です。';
  FLightY.ShowHint:=True; FLightY.Hint:='ペン先を基準にした光源方向。上から照らすと影が下へ伸びます。AviUtl2側と共通です。';
  L:=TLabel.Create(Self); L.Parent:=Scroll; L.AutoSize:=False; L.SetBounds(12,Y+152,304,80); L.WordWrap:=True;
  L.Caption:='インストール済みのフォントを使用します。文字形状は保持し、書き順だけを推定・学習します。筆圧や高度な縦組みは今後調整します。';
  HelpPanel:=TPanel.Create(Self); HelpPanel.Parent:=FPreviewPage; HelpPanel.Align:=alBottom; HelpPanel.Height:=50; HelpPanel.BevelOuter:=bvNone;
  FTimeLabel:=TLabel.Create(Self); FTimeLabel.Parent:=HelpPanel; FTimeLabel.AutoSize:=False;
  FTimeLabel.SetBounds(353,13,HelpPanel.Width-513,28); FTimeLabel.Anchors:=[akTop,akLeft,akRight];
  B:=AddButton(HelpPanel,'先頭から再生',HelpPanel.Width-148,8,132,RestartClick); B.Anchors:=[akTop,akRight];
  FPreviewPaint:=TWritingPaintBox.Create(Self); FPreviewPaint.Parent:=FPreviewPage; FPreviewPaint.Align:=alClient; FPreviewPaint.OnPaint:=PaintPreview;
  LeftPanel:=TPanel.Create(Self); LeftPanel.Parent:=FEditPage; LeftPanel.Align:=alLeft; LeftPanel.Width:=154; LeftPanel.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=LeftPanel; L.Align:=alTop; L.Height:=29; L.Caption:=' 文字一覧 / 学習状態';
  FChars:=TListBox.Create(Self); FChars.Parent:=LeftPanel; FChars.Align:=alClient;
  FChars.Style:=lbOwnerDrawFixed; FChars.ItemHeight:=48; FChars.OnDrawItem:=DrawCharacter; FChars.OnClick:=SelectCharacter;
  RightPanel:=TPanel.Create(Self); RightPanel.Parent:=FEditPage; RightPanel.Align:=alRight; RightPanel.Width:=225; RightPanel.BevelOuter:=bvNone;
  L:=TLabel.Create(Self); L.Parent:=RightPanel; L.AutoSize:=False; L.Align:=alTop; L.Height:=44;
  L.Caption:=' 画一覧 — ドラッグで移動'+sLineBreak+' Ctrl / Shiftで複数選択・右クリック';
  FStrokes:=TWritingStrokeListBox.Create(Self); FStrokes.Parent:=RightPanel; FStrokes.Align:=alClient;
  FStrokes.MultiSelect:=True; FStrokes.ExtendedSelect:=True; FStrokes.DragMode:=dmAutomatic;
  FStrokes.Style:=lbOwnerDrawFixed; FStrokes.ItemHeight:=48; FStrokes.OnDrawItem:=DrawStroke;
  FStrokes.OnClick:=SelectStroke; FStrokes.OnMouseDown:=StrokeMouseDown;
  FStrokes.OnDragOver:=StrokeDragOver; FStrokes.OnDragDrop:=StrokeDragDrop;
  FStrokes.OnStartDrag:=StrokeStartDrag; FStrokes.OnEndDrag:=StrokeEndDrag; FStrokes.OnContextPopup:=StrokeContext;
  HelpPanel:=TPanel.Create(Self); HelpPanel.Parent:=FEditPage; HelpPanel.Align:=alBottom; HelpPanel.Height:=78; HelpPanel.BevelOuter:=bvNone;
  FEditorStatus:=TLabel.Create(Self); FEditorStatus.Parent:=HelpPanel; FEditorStatus.Align:=alClient;
  FEditorStatus.AutoSize:=False; FEditorStatus.ShowHint:=True;
  FEditorStatus.WordWrap:=True; FEditorStatus.Caption:='文字を選択してください。Space: 1文字を再生 / 停止。画を選び、中央の経路点をドラッグして補正できます。';
  FEditPaint:=TWritingPaintBox.Create(Self); FEditPaint.Parent:=FEditPage; FEditPaint.Align:=alClient; FEditPaint.OnPaint:=PaintEditor;
  FEditPaint.OnMouseDown:=PathMouseDown; FEditPaint.OnMouseMove:=PathMouseMove; FEditPaint.OnMouseUp:=PathMouseUp;
  FEditPaint.OnContextPopup:=PathContext; CreateEditorMenus;
  FTimer:=TTimer.Create(Self); FTimer.Interval:=33; FTimer.OnTimer:=Tick;
  FUpdating:=False; Rebuild;
end;

destructor TWritingSettingsForm.Destroy;
begin
  if FTimer<>nil then FTimer.Enabled:=False;
  FCurrent:=nil; FUndo.Free; FRedo.Free; FDisplayBitmap.Free; FEditEngine.Free; FSingle.Free; FPreview.Free; inherited;
end;

procedure TWritingSettingsForm.ReadControls;
var K: TCharacterKind;
begin
  FSettings.Text:=Copy(FMemo.Text,1,AW_MAX_TEXT); FSettings.FontSize:=FSize.Value;
  if FSpeedChanged then FSettings.Speed:=FSpeed.Value;
  FSettings.Pen:=AW_PEN_ORDER[EnsureRange(FPen.ItemIndex,Low(AW_PEN_ORDER),High(AW_PEN_ORDER))];
  FSettings.Vertical:=FDirection.ItemIndex=1; FSettings.ShowPen:=FShowPen.Checked;
  FSettings.LetterGap:=FLetter.Value/100; FSettings.LineGap:=FLine.Value/100;
  for K:=Low(K) to High(K) do FSettings.Ratios[K]:=FRatios[K].Value/100;
  if FPenSizeChanged then FSettings.PenSize:=FPenSize.ValueFloat/100;
  FSettings.LiftHeight:=FLift.Value;
  if FAngleChanged then FSettings.PenAngle:=FAngle.Value;
  if FLightXChanged then FSettings.LightX:=FLightX.Value;
  if FLightYChanged then FSettings.LightY:=FLightY.Value;
end;

procedure TWritingSettingsForm.Changed(Sender: TObject);
begin
  if FUpdating then Exit;
  if Sender=FSpeed then FSpeedChanged:=True;
  if Sender=FAngle then FAngleChanged:=True;
  if Sender=FLightX then FLightXChanged:=True;
  if Sender=FLightY then FLightYChanged:=True;
  if Sender=FPenSize then FPenSizeChanged:=True;
  FDirty:=True; FChangedAt:=GetTickCount64;
end;

procedure TWritingSettingsForm.Rebuild;
var C,Previous: string; I: Integer;
begin
  ReadControls; FDirty:=False; FPaused:=False; FSinglePlaying:=False;
  FCurrent:=nil; FPreview.Prepare(FSettings); FEditEngine.Configure(FSettings);
  FTimeLabel.Caption:=Format('筆記完了: %.2f 秒  /  %.0f px',[FPreview.Duration(FSettings),FPreview.TotalDistance]);
  Previous:=''; if FChars.ItemIndex>=0 then Previous:=FChars.Items[FChars.ItemIndex];
  FChars.Items.BeginUpdate;
  try
    FChars.Clear;
    for C in UnicodeCharacters(FSettings.Text) do
      if (C<>#10) and (C<>#9) and (C<>' ') and (C<>'　') and (FChars.Items.IndexOf(C)<0) then FChars.Items.Add(C);
    I:=FChars.Items.IndexOf(Previous); if (I<0) and (FChars.Count>0) then I:=0;
    FChars.ItemIndex:=I;
  finally FChars.Items.EndUpdate end;
  SelectCharacter(nil); FPreviewPaint.Invalidate;
  if FPreview.Engine.Warnings<>'' then FStatus.Caption:=FPreview.Engine.Warnings
  else FStatus.Caption:='閉じると文章・設定を反映します。Space: 一時停止 / 再開（入力中を除く）';
  FStatus.Hint:=FStatus.Caption;
  FStart:=GetTickCount64;
end;

procedure TWritingSettingsForm.Tick(Sender: TObject);
begin
  try
    if FDirty and (GetTickCount64-FChangedAt>=300) then Rebuild;
    if FPages.ActivePage=FPreviewPage then
    begin if not FPaused then FPreviewPaint.Invalidate end
    else if FSinglePlaying then FEditPaint.Invalidate;
  except
    on E: Exception do begin FDirty:=False; FPaused:=True; FSinglePlaying:=False; FStatus.Caption:=E.Message end;
  end;
end;

procedure TWritingSettingsForm.DrawPixels(Canvas: TCanvas; const Rect: TRect;
  const Pixels: TWritingPixels; W,H: Integer);
var X,Y,I,A,BG: Integer; Row: PByte;
begin
    // 同じ寸法のDIBとRGBA配列は再利用し、毎フレームのGDI資源確保を避ける。
    if (FDisplayBitmap.Width<>W) or (FDisplayBitmap.Height<>H) then FDisplayBitmap.SetSize(W,H);
    GdiFlush;
    for Y:=0 to H-1 do
    begin
      Row:=FDisplayBitmap.ScanLine[Y];
      for X:=0 to W-1 do
      begin
        I:=Y*W+X; A:=Pixels[I].A; BG:=250; if ((X div 20+Y div 20) mod 2)=0 then BG:=240;
        Row[X*4]:=(Pixels[I].B*A+BG*(255-A)+127) div 255;
        Row[X*4+1]:=(Pixels[I].G*A+BG*(255-A)+127) div 255;
        Row[X*4+2]:=(Pixels[I].R*A+BG*(255-A)+127) div 255; Row[X*4+3]:=255;
      end;
    end;
    if (Rect.Width=W) and (Rect.Height=H) then
      BitBlt(Canvas.Handle,Rect.Left,Rect.Top,W,H,FDisplayBitmap.Canvas.Handle,0,0,SRCCOPY)
    else Canvas.StretchDraw(Rect,FDisplayBitmap);
end;

procedure TWritingSettingsForm.PaintPreview(Sender: TObject);
var S: TWritingSettings; Time,Duration,Fit: Double; W,H: Integer;
begin
  try
    W:=Max(1,FPreviewPaint.Width); H:=Max(1,FPreviewPaint.Height); S:=FSettings;
    S.X:=0; S.Y:=0; S.Transparency:=0; S.Scale:=100;
    FPreview.Prepare(S); Fit:=Min((W-110)/Max(1,FPreview.Bounds.Width),(H-110)/Max(1,FPreview.Bounds.Height));
    S.Scale:=Min(100,Fit*100);
    if FPaused then Time:=(FPausedAt-FStart)/1000 else Time:=(GetTickCount64-FStart)/1000;
    Duration:=FPreview.Duration(S)+1.2;
    if Duration>0 then Time:=Time-Floor(Time/Duration)*Duration;
    FPreview.Render(nil,W,H,Time,S,FPreviewPixels);
    DrawPixels(FPreviewPaint.Canvas,FPreviewPaint.ClientRect,FPreviewPixels,W,H);
  except on E: Exception do begin FPreviewPaint.Canvas.TextOut(20,20,E.Message); FStatus.Caption:=E.Message end end;
end;

procedure TWritingSettingsForm.PickFont(Sender: TObject);
var D: TFontDialog;
begin
  D:=TFontDialog.Create(Self);
  try
    D.Options:=[fdTrueTypeOnly,fdForceFontExist]; D.Font.Name:=FSettings.FontName; D.Font.Size:=20;
    D.Font.Style:=[]; if FSettings.Bold then D.Font.Style:=D.Font.Style+[fsBold];
    if FSettings.Italic then D.Font.Style:=D.Font.Style+[fsItalic];
    if D.Execute then
    begin
      FSettings.FontName:=D.Font.Name; FSettings.Bold:=fsBold in D.Font.Style; FSettings.Italic:=fsItalic in D.Font.Style;
      FFontButton.Caption:=D.Font.Name; Changed(nil);
    end;
  finally D.Free end;
end;

procedure TWritingSettingsForm.PickColor(Sender: TObject);
var D: TColorDialog; C: Cardinal;
begin
  D:=TColorDialog.Create(Self);
  try
    C:=FSettings.InkColor; D.Color:=RGB((C shr 16) and 255,(C shr 8) and 255,C and 255);
    if D.Execute then
    begin C:=ColorToRGB(D.Color); FSettings.InkColor:=((C and 255) shl 16) or (C and $FF00) or ((C shr 16) and 255); Changed(nil) end;
  finally D.Free end;
end;

procedure TWritingSettingsForm.FormKey(Sender: TObject; var Key: Word; Shift: TShiftState);
var Action: Integer;
begin
  if ActiveControl is TCustomEdit then Exit;
  if FPages.ActivePage=FEditPage then
  begin
    Action:=0;
    if ssCtrl in Shift then
      case Key of
        Ord('K'): Action:=EA_SPLIT; Ord('J'): Action:=EA_JOIN;
        Ord('I'): Action:=EA_VERTEX;
        Ord('R'): if ssShift in Shift then Action:=EA_RESET else Action:=EA_REVERSE;
        Ord('Z'): Action:=EA_UNDO; Ord('Y'): Action:=EA_REDO; Ord('A'): Action:=EA_SELECTALL;
      end
    else if ssAlt in Shift then
      case Key of VK_UP: Action:=EA_UP; VK_DOWN: Action:=EA_DOWN end;
    if Action<>0 then begin ExecuteEditAction(Action); Key:=0; Exit end;
  end;
  if Key<>VK_SPACE then Exit;
  Key:=0;
  if FPages.ActivePage=FPreviewPage then
  begin
    if FPaused then FStart:=FStart+(GetTickCount64-FPausedAt) else FPausedAt:=GetTickCount64;
    FPaused:=not FPaused; FPreviewPaint.Invalidate;
  end
  else ExecuteEditAction(EA_PLAY);
end;

procedure TWritingSettingsForm.RestartClick(Sender: TObject);
begin FStart:=GetTickCount64; FPaused:=False; FPreviewPaint.Invalidate end;

procedure TWritingSettingsForm.PageChanged(Sender: TObject);
begin
  if FDirty then Rebuild;
  FSinglePlaying:=False; SelectCharacter(nil);
end;

procedure TWritingSettingsForm.SelectCharacter(Sender: TObject);
var Key: string;
begin
  FCurrent:=nil; FSinglePlaying:=False; FDragPoint:=-1; FSelectedPoint:=-1;
  if FChars.ItemIndex>=0 then FCurrent:=FEditEngine.Glyph(FChars.Items[FChars.ItemIndex]);
  Key:=''; if FCurrent<>nil then Key:=FCurrent.FontID+'|'+FCurrent.Character;
  if Key<>FHistoryKey then begin FUndo.Clear; FRedo.Clear; FHistoryKey:=Key end;
  FSelectedHit.Stroke:=-1;
  UpdateStrokeList; FEditPaint.Invalidate;
end;

procedure TWritingSettingsForm.UpdateStrokeList;
var I,Selected: Integer; Indices: TArray<Integer>;
begin
  Selected:=FStrokes.ItemIndex; Indices:=SelectedStrokes; FStrokes.Items.BeginUpdate;
  try
    FStrokes.Clear;
    FVertices:=nil;
    if FCurrent<>nil then
    begin
      SetLength(FVertices,Length(FCurrent.Strokes));
      for I:=0 to High(FVertices) do FVertices[I]:=EditingVertices(FCurrent.Strokes[I]);
    end;
    if FCurrent<>nil then for I:=0 to High(FCurrent.Strokes) do FStrokes.Items.Add(IntToStr(I+1));
    SetStrokeSelection(Indices);
    if (FStrokes.Count>0) and (FStrokes.SelCount=0) then SetStrokeSelection([EnsureRange(Selected,0,FStrokes.Count-1)]);
  finally FStrokes.Items.EndUpdate end;
  FChars.Invalidate;
  UpdateEditorStatus;
end;

procedure TWritingSettingsForm.SelectStroke(Sender: TObject);
begin
  FSelectedPoint:=-1; FSelectedHit.Stroke:=-1; FSinglePlaying:=False;
  UpdateEditorStatus; FEditPaint.Invalidate;
end;

procedure TWritingSettingsForm.UpdateEditorStatus;
var Text,State: string;
begin
  if FEditorMenu<>nil then MenuPopup(FEditorMenu);
  if FStrokeMenu<>nil then MenuPopup(FStrokeMenu);
  if FCurrent=nil then begin FEditorStatus.Caption:='文字を選択してください。'; Exit end;
  State:='自動推定'; if FCurrent.Learned then State:='学習済み';
  Text:=FCurrent.Character+' — '+State+' / '+IntToStr(Length(FCurrent.Strokes))+' 画。';
  if FSelectedHit.Stroke>=0 then Text:=Text+Format(' 選択位置: %d画目。右クリック→頂点作成／分割。',[FSelectedHit.Stroke+1])
  else Text:=Text+' 線を右クリック→頂点作成／分割。重なりは色付き候補から選択。';
  Text:=Text+Format(' 選択中: %d画。太線＝選択、●始点 → □終点。',[FStrokes.SelCount]);
  Text:=Text+' 画一覧はCtrl/Shiftで複数選択→右クリックで結合。';
  FEditorStatus.Caption:=Text; FEditorStatus.Hint:=Text;
end;

procedure TWritingSettingsForm.CommitEdit(const Before: TGlyphEditState; Save: Boolean);
begin
  FUndo.Add(Before); if FUndo.Count>50 then FUndo.Delete(0); FRedo.Clear;
  FSelectedHit.Stroke:=-1; FSelectedPoint:=-1;
  if Save then PersistCurrent else begin UpdateStrokeList; FEditPaint.Invalidate end;
end;

procedure TWritingSettingsForm.ApplyHistory(Redo: Boolean);
var FromList,ToList: TList<TGlyphEditState>; Before,Target: TGlyphEditState;
begin
  if FCurrent=nil then Exit;
  FromList:=FUndo; ToList:=FRedo; if Redo then begin FromList:=FRedo; ToList:=FUndo end;
  if FromList.Count=0 then Exit;
  Before:=CaptureGlyphState(FCurrent); Target:=FromList.Last;
  try
    RestoreGlyphState(FCurrent,Target);
    if Target.Learned then SaveGlyphLearning(FCurrent) else DeleteGlyphLearning(FCurrent,False);
    FromList.Delete(FromList.Count-1); ToList.Add(Before);
    if ToList.Count>50 then ToList.Delete(0);
    FSelectedHit.Stroke:=-1; FSelectedPoint:=-1; FSinglePlaying:=False;
    UpdateStrokeList; FEditPaint.Invalidate;
  except
    on E: Exception do begin RestoreGlyphState(FCurrent,Before); MessageDlg(E.Message,mtError,[mbOK],0) end;
  end;
end;

procedure TWritingSettingsForm.PersistCurrent;
begin
  if FCurrent=nil then Exit;
  try
    SaveGlyphLearning(FCurrent); UpdateStrokeList; FEditPaint.Invalidate;
    FSinglePlaying:=False; FSingleStart:=GetTickCount64;
  except on E: Exception do MessageDlg('学習を保存できませんでした。'+sLineBreak+E.Message,mtError,[mbOK],0) end;
end;

procedure TWritingSettingsForm.StrokeMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var I: Integer;
begin
  if Button<>mbRight then Exit;
  I:=FStrokes.ItemAtPos(Point(X,Y),True);
  if (I>=0) and not FStrokes.Selected[I] then begin SetStrokeSelection([I]); SelectStroke(nil) end;
end;

procedure TWritingSettingsForm.StrokeStartDrag(Sender: TObject; var DragObject: TDragObject);
begin FDragIndices:=SelectedStrokes; FSelectedHit.Stroke:=-1; FSelectedPoint:=-1 end;

procedure TWritingSettingsForm.StrokeEndDrag(Sender,Target: TObject; X,Y: Integer);
begin FStrokes.DropIndex:=-1; FDragIndices:=nil end;

procedure TWritingSettingsForm.StrokeDragOver(Sender,Source: TObject; X,Y: Integer; State: TDragState; var Accept: Boolean);
var I: Integer; R: TRect;
begin
  Accept:=(Source=FStrokes) and (FCurrent<>nil) and (Length(FDragIndices)>0);
  // VCLはドロップ直前にもLeaveで受理可否を問い合わせるため、Leave自体を拒否しない。
  if not Accept or (State=dsDragLeave) then begin FStrokes.DropIndex:=-1; Exit end;
  I:=FStrokes.ItemAtPos(Point(X,Y),True);
  if I<0 then I:=FStrokes.Count
  else begin R:=FStrokes.ItemRect(I); if Y>=(R.Top+R.Bottom) div 2 then Inc(I) end;
  FStrokes.DropIndex:=I;
end;

procedure TWritingSettingsForm.StrokeDragDrop(Sender,Source: TObject; X,Y: Integer);
var Before: TGlyphEditState; After: TArray<Integer>; Target: Integer; R: TRect;
begin
  if (Source<>FStrokes) or (FCurrent=nil) then Exit;
  Target:=FStrokes.ItemAtPos(Point(X,Y),True);
  if Target<0 then Target:=FStrokes.Count
  else begin R:=FStrokes.ItemRect(Target); if Y>=(R.Top+R.Bottom) div 2 then Inc(Target) end;
  Before:=CaptureGlyphState(FCurrent);
  if MoveSelectedStrokes(FCurrent,FDragIndices,Target,After) then
  begin CommitEdit(Before); SetStrokeSelection(After); UpdateEditorStatus end;
  FStrokes.DropIndex:=-1;
end;

procedure TWritingSettingsForm.PaintEditor(Sender: TObject);
var C: TCanvas; I,X,Y: Integer; R: TRect; S: TWritingSettings;
  Time,Duration,Fit: Double; Bitmap: TBitmap; Row: PByte; A: Integer;
  function ScreenPoint(const P: TPointF): TPointF;
  begin Result:=PointF(FViewX+P.X*FViewScale,FViewY+P.Y*FViewScale) end;
  function Selected(Index: Integer): Boolean;
  begin Result:=(Index<FStrokes.Count) and FStrokes.Selected[Index] end;
  function PathColor(Index: Integer; Active: Boolean): TColor;
  var Color: Cardinal;
  begin
    Result:=STROKE_COLORS[Index mod 10]; if Active then Exit;
    Color:=ColorToRGB(Result);
    Result:=RGB((GetRValue(Color)+510) div 3,(GetGValue(Color)+510) div 3,(GetBValue(Color)+510) div 3);
  end;
  procedure Trace(Index: Integer; Color: TColor; Width: Integer);
  var J: Integer; P: TPointF;
  begin
    C.Pen.Color:=Color; C.Pen.Width:=Width; C.Pen.Style:=psSolid;
    for J:=0 to High(FCurrent.Strokes[Index].Points) do
    begin
      P:=ScreenPoint(FCurrent.Strokes[Index].Points[J]);
      if J=0 then C.MoveTo(Round(P.X),Round(P.Y)) else C.LineTo(Round(P.X),Round(P.Y));
    end;
  end;
  procedure Handles(Index: Integer; Active: Boolean);
  var J,X,Y,Radius: Integer; P: TPointF;
  begin
    Radius:=3; if Active then Radius:=4;
    C.Brush.Style:=bsSolid; C.Brush.Color:=PathColor(Index,Active); C.Pen.Color:=clWhite; C.Pen.Width:=1;
    for J in FVertices[Index] do
    begin
      P:=ScreenPoint(FCurrent.Strokes[Index].Points[J]);
      X:=Round(P.X); Y:=Round(P.Y); C.Ellipse(X-Radius,Y-Radius,X+Radius+1,Y+Radius+1);
    end;
  end;
  procedure LabelAt(const P: TPointF; const Text: string; Color: TColor);
  var X,Y,W,H: Integer;
  begin
    C.Font.Size:=10; C.Font.Style:=[fsBold]; C.Font.Color:=Color;
    W:=C.TextWidth(Text)+8; H:=C.TextHeight(Text)+4;
    X:=EnsureRange(Round(P.X),2,Max(2,FEditPaint.Width-W-2));
    Y:=EnsureRange(Round(P.Y),2,Max(2,FEditPaint.Height-H-2));
    C.Brush.Style:=bsSolid; C.Brush.Color:=clWhite; C.Pen.Color:=clWhite; C.Pen.Width:=1;
    C.RoundRect(X,Y,X+W,Y+H,5,5); C.TextOut(X+4,Y+2,Text);
  end;
  procedure ArrowAt(Index: Integer; AtDistance,Size: Double);
  var J: Integer; P,Q,Tip: TPointF; Len,T,DX,DY: Double; Points: array[0..2] of TPoint;
  begin
    for J:=1 to High(FCurrent.Strokes[Index].Points) do
    begin
      P:=ScreenPoint(FCurrent.Strokes[Index].Points[J-1]); Q:=ScreenPoint(FCurrent.Strokes[Index].Points[J]);
      Len:=Distance(P,Q); if Len<1E-6 then Continue;
      if AtDistance>Len then begin AtDistance:=AtDistance-Len; Continue end;
      T:=AtDistance/Len; DX:=(Q.X-P.X)/Len; DY:=(Q.Y-P.Y)/Len;
      Tip:=PointF(P.X+(Q.X-P.X)*T,P.Y+(Q.Y-P.Y)*T);
      Points[0]:=Point(Round(Tip.X),Round(Tip.Y));
      Points[1]:=Point(Round(Tip.X-DX*Size-DY*Size*0.55),Round(Tip.Y-DY*Size+DX*Size*0.55));
      Points[2]:=Point(Round(Tip.X-DX*Size+DY*Size*0.55),Round(Tip.Y-DY*Size-DX*Size*0.55));
      C.Brush.Style:=bsSolid; C.Brush.Color:=STROKE_COLORS[Index mod 10];
      C.Pen.Color:=clWhite; C.Pen.Width:=4; C.Polygon(Points);
      C.Pen.Color:=$303038; C.Pen.Width:=1; C.Polygon(Points); Exit;
    end;
  end;
  procedure DirectionAndEnds(Index: Integer);
  var P,Q: TPointF; J,X,Y: Integer; Total,At,ArrowSize: Double; Color: TColor;
  begin
    if Length(FCurrent.Strokes[Index].Points)=0 then Exit;
    P:=ScreenPoint(FCurrent.Strokes[Index].Points[0]);
    Q:=ScreenPoint(FCurrent.Strokes[Index].Points[High(FCurrent.Strokes[Index].Points)]);
    Color:=STROKE_COLORS[Index mod 10]; Total:=0;
    for J:=1 to High(FCurrent.Strokes[Index].Points) do
      Total:=Total+Distance(FCurrent.Strokes[Index].Points[J-1],FCurrent.Strokes[Index].Points[J])*FViewScale;
    if Total>2 then
    begin
      ArrowSize:=Min(14,Max(6,Total/3)); At:=42;
      while At<Total-38 do begin ArrowAt(Index,At,ArrowSize); At:=At+74 end;
      ArrowAt(Index,Max(Total/2,Total-22),ArrowSize);
    end;
    // 白い四角が終点、塗りつぶした丸が始点。閉じた経路では両方を同じ位置に重ねる。
    X:=Round(Q.X); Y:=Round(Q.Y); C.Brush.Style:=bsSolid; C.Brush.Color:=clWhite;
    C.Pen.Color:=clWhite; C.Pen.Width:=6; C.Rectangle(X-11,Y-11,X+12,Y+12);
    C.Pen.Color:=Color; C.Pen.Width:=3; C.Rectangle(X-11,Y-11,X+12,Y+12);
    X:=Round(P.X); Y:=Round(P.Y); C.Brush.Color:=Color; C.Pen.Color:=clWhite; C.Pen.Width:=3;
    C.Ellipse(X-9,Y-9,X+10,Y+10); C.Pen.Color:=$303038; C.Pen.Width:=1;
    C.Brush.Style:=bsClear; C.Ellipse(X-9,Y-9,X+10,Y+10);
    if Distance(P,Q)<26 then
      LabelAt(PointF((P.X+Q.X)/2+18,(P.Y+Q.Y)/2-30),Format('%d 始点・終点',[Index+1]),Color)
    else begin
      LabelAt(PointF(P.X+16,P.Y-30),Format('%d 始点',[Index+1]),Color);
      LabelAt(PointF(Q.X+16,Q.Y+12),Format('%d 終点',[Index+1]),Color);
    end;
  end;
begin
  C:=FEditPaint.Canvas; C.Brush.Style:=bsSolid; C.Pen.Style:=psSolid;
  C.Brush.Color:=$FAFAFA; C.FillRect(FEditPaint.ClientRect); if FCurrent=nil then Exit;
  if FSinglePlaying then
  begin
    S:=FSettings; S.Text:=FCurrent.Character; S.X:=0; S.Y:=0; S.Transparency:=0; S.Scale:=100;
    S.FontSize:=128; FSingle.Prepare(S);
    Fit:=Min((FEditPaint.Width-130)/Max(1,FSingle.Bounds.Width),(FEditPaint.Height-130)/Max(1,FSingle.Bounds.Height));
    S.Scale:=Min(280,Fit*100); Duration:=FSingle.Duration(S)+0.8;
    Time:=(GetTickCount64-FSingleStart)/1000; if Duration>0 then Time:=Time-Floor(Time/Duration)*Duration;
    try
      FSingle.Render(nil,Max(1,FEditPaint.Width),Max(1,FEditPaint.Height),Time,S,FSinglePixels);
      DrawPixels(C,FEditPaint.ClientRect,FSinglePixels,FEditPaint.Width,FEditPaint.Height);
    except on E: Exception do C.TextOut(10,10,E.Message) end;
    Exit;
  end;
  FViewScale:=Min((FEditPaint.Width-100)/Max(1,FCurrent.Width),(FEditPaint.Height-100)/Max(1,FCurrent.Height));
  FViewScale:=Max(0.1,FViewScale); FViewX:=(FEditPaint.Width-FCurrent.Width*FViewScale)/2;
  FViewY:=(FEditPaint.Height-FCurrent.Height*FViewScale)/2;
  Bitmap:=TBitmap.Create;
  try
    Bitmap.PixelFormat:=pf32bit; Bitmap.SetSize(Max(1,FCurrent.Width),Max(1,FCurrent.Height));
    for Y:=0 to FCurrent.Height-1 do
    begin
      Row:=Bitmap.ScanLine[Y];
      for X:=0 to FCurrent.Width-1 do
      begin A:=255-FCurrent.Mask[Y*FCurrent.Width+X] div 5;
        Row[X*4]:=A; Row[X*4+1]:=A; Row[X*4+2]:=A; Row[X*4+3]:=255 end;
    end;
    R:=Rect(Round(FViewX),Round(FViewY),Round(FViewX+FCurrent.Width*FViewScale),Round(FViewY+FCurrent.Height*FViewScale));
    C.StretchDraw(R,Bitmap);
  finally Bitmap.Free end;
  // 非選択経路を先に薄く描き、選択した経路を最後に白黒の縁と8pxの色線で重ねる。
  for I:=0 to High(FCurrent.Strokes) do
  begin
    if Selected(I) then Continue;
    Trace(I,PathColor(I,False),2); Handles(I,False);
    if Length(FCurrent.Strokes[I].Points)=0 then Continue;
    var P: TPointF; P:=ScreenPoint(FCurrent.Strokes[I].Points[0]);
    C.Font.Size:=9; C.Font.Style:=[]; C.Font.Color:=STROKE_COLORS[I mod 10]; C.Brush.Style:=bsClear;
    C.TextOut(Round(P.X)+7,Round(P.Y)-18,IntToStr(I+1));
  end;
  for I:=0 to High(FCurrent.Strokes) do if Selected(I) then
  begin
    Trace(I,clWhite,14); Trace(I,$303038,11); Trace(I,STROKE_COLORS[I mod 10],8);
    Handles(I,True); DirectionAndEnds(I);
  end;
  // 選択点は全経路より手前に、元の画の色と大きな白黒の縁で確実に表示する。
  if (FSelectedHit.Stroke>=0) and (FSelectedHit.Stroke<Length(FCurrent.Strokes)) then
  begin
    X:=Round(FViewX+FSelectedHit.Point.X*FViewScale); Y:=Round(FViewY+FSelectedHit.Point.Y*FViewScale);
    C.Pen.Color:=clWhite; C.Pen.Width:=4; C.Brush.Style:=bsSolid;
    C.Brush.Color:=STROKE_COLORS[FSelectedHit.Stroke mod 10]; C.Ellipse(X-12,Y-12,X+13,Y+13);
    C.Pen.Color:=clBlack; C.Pen.Width:=2; C.Brush.Style:=bsClear; C.Ellipse(X-12,Y-12,X+13,Y+13);
    C.Font.Size:=11; C.Font.Color:=clBlack;
    if FSelectedPoint<0 then C.TextOut(X+16,Y-19,Format('%d画目・線上',[FSelectedHit.Stroke+1]))
    else C.TextOut(X+16,Y-19,Format('%d画目・頂点',[FSelectedHit.Stroke+1]));
  end;
end;

procedure TWritingSettingsForm.PathMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var J: Integer; P,Screen: TPoint; Hit: TStrokeHit;
begin
  if (Button<>mbLeft) or (FCurrent=nil) then Exit;
  if FSinglePlaying then begin FSinglePlaying:=False; FEditPaint.Repaint end;
  if FViewScale<=0 then Exit;
  FEditPaint.SetFocus; Hit.Stroke:=-1; J:=-1;
  if (FSelectedHit.Stroke>=0) and
    (Hypot(FViewX+FSelectedHit.Point.X*FViewScale-X,FViewY+FSelectedHit.Point.Y*FViewScale-Y)<=10) and
    not (ssAlt in Shift) then
  begin
    Hit:=FSelectedHit; J:=FSelectedPoint;
  end;
  if Hit.Stroke<0 then
  begin
    GatherPointChoices(X,Y);
    if Length(FPointHits)>1 then
    begin
      PopulatePointChoices(FPointMenu.Items); P:=FEditPaint.ClientToScreen(Point(X+10,Y+10));
      FPointMenu.Popup(P.X,P.Y); Exit;
    end;
    if Length(FPointHits)=1 then begin Hit:=FPointHits[0]; J:=FPointIndices[0] end
    else Hit:=HitStroke(FCurrent,PointF((X-FViewX)/FViewScale,(Y-FViewY)/FViewScale),14/FViewScale,FStrokes.ItemIndex);
  end;
  if Hit.Stroke<0 then Exit;
  SelectPathPoint(Hit,J); FPathChanged:=False; FDragPoint:=J;
  if J>=0 then
  begin
    FDragBefore:=CaptureGlyphState(FCurrent); Screen:=Point(X,Y); FDragOrigin:=Screen;
    FEditPaint.MouseCapture:=True;
  end;
end;

procedure TWritingSettingsForm.PathMouseMove(Sender: TObject; Shift: TShiftState; X,Y: Integer);
var I,J: Integer; Original,Target: TPointF;
begin
  if (FCurrent=nil) or FSinglePlaying or (FViewScale<=0) then Exit;
  if FDragPoint<0 then Exit; I:=FSelectedHit.Stroke; if I<0 then Exit;
  if not FPathChanged and (Hypot(X-FDragOrigin.X,Y-FDragOrigin.Y)<4) then Exit;
  Original:=FDragBefore.Strokes[I].Points[FDragPoint];
  Target:=PointF(
    EnsureRange(Original.X+(X-FDragOrigin.X)/FViewScale,0.0,Max(0,FCurrent.Width-1)*1.0),
    EnsureRange(Original.Y+(Y-FDragOrigin.Y)/FViewScale,0.0,Max(0,FCurrent.Height-1)*1.0));
  if not MovePathVertex(FDragBefore.Strokes[I],FDragPoint,Target,FCurrent.Strokes[I]) then Exit;
  for J:=0 to High(FCurrent.Strokes[I].Points) do
  begin
    FCurrent.Strokes[I].Points[J].X:=EnsureRange(FCurrent.Strokes[I].Points[J].X,0.0,Max(0,FCurrent.Width-1)*1.0);
    FCurrent.Strokes[I].Points[J].Y:=EnsureRange(FCurrent.Strokes[I].Points[J].Y,0.0,Max(0,FCurrent.Height-1)*1.0);
  end;
  FPathChanged:=True;
  FSelectedHit.Point:=FCurrent.Strokes[I].Points[FDragPoint];
  FEditPaint.Invalidate;
end;

procedure TWritingSettingsForm.PathMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
var Hit: TStrokeHit; J: Integer;
begin
  if (Button<>mbLeft) or (FDragPoint<0) then Exit;
  Hit:=FSelectedHit; J:=FDragPoint; FDragPoint:=-1; FEditPaint.MouseCapture:=False;
  if FPathChanged then
  begin PrepareGlyphTiming(FCurrent); CommitEdit(FDragBefore); SelectPathPoint(Hit,J) end
  else FEditPaint.Invalidate;
end;

procedure TWritingSettingsForm.DrawCharacter(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var C: TCanvas; G: TWritingGlyph;
begin
  C:=FChars.Canvas; C.FillRect(Rect); C.Font.Size:=24; C.Font.Name:=FSettings.FontName;
  C.TextOut(Rect.Left+6,Rect.Top+1,FChars.Items[Index]); C.Font.Name:=Font.Name; C.Font.Size:=9;
  G:=FEditEngine.Glyph(FChars.Items[Index]);
  if G.Missing then C.TextOut(Rect.Left+61,Rect.Top+17,'未収録')
  else if G.Learned then C.TextOut(Rect.Left+61,Rect.Top+17,'学習済')
  else C.TextOut(Rect.Left+61,Rect.Top+17,'推定');
end;

procedure TWritingSettingsForm.DrawStroke(Control: TWinControl; Index: Integer; Rect: TRect; State: TOwnerDrawState);
var C: TCanvas; J: Integer; P: TPointF; Fit: Double;
begin
  C:=FStrokes.Canvas;
  if odSelected in State then begin C.Brush.Color:=clHighlight; C.Font.Color:=clHighlightText end
  else begin C.Brush.Color:=clWindow; C.Font.Color:=clWindowText end;
  C.FillRect(Rect); if (FCurrent=nil) or (Index>=Length(FCurrent.Strokes)) then Exit;
  C.Pen.Color:=clWhite; C.Pen.Width:=2; C.Brush.Color:=STROKE_COLORS[Index mod 10];
  C.Ellipse(Rect.Left+8,Rect.Top+14,Rect.Left+29,Rect.Top+35);
  Fit:=32/Max(1,Max(FCurrent.Width,FCurrent.Height));
  C.Pen.Color:=STROKE_COLORS[Index mod 10]; C.Pen.Width:=2;
  for J:=0 to High(FCurrent.Strokes[Index].Points) do
  begin
    P:=FCurrent.Strokes[Index].Points[J];
    if J=0 then C.MoveTo(Rect.Left+42+Round(P.X*Fit),Rect.Top+8+Round(P.Y*Fit))
    else C.LineTo(Rect.Left+42+Round(P.X*Fit),Rect.Top+8+Round(P.Y*Fit));
  end;
  C.Brush.Style:=bsClear; C.Font.Size:=10; C.TextOut(Rect.Left+88,Rect.Top+14,IntToStr(Index+1)+' 画');
  if FCurrent.Strokes[Index].Reversed then C.TextOut(Rect.Left+148,Rect.Top+14,'反転');
  C.Brush.Style:=bsSolid;
end;

procedure TWritingSettingsForm.CloseSettings(Sender: TObject; var CanClose: Boolean);
begin
  CanClose:=False;
  try
    ReadControls; FPreview.Prepare(FSettings); CanClose:=True;
  except on E: Exception do MessageDlg(E.Message,mtError,[mbOK],0) end;
end;

function EditWritingSettings(var Settings: TWritingSettings): Boolean;
var Form: TWritingSettingsForm;
begin
  Form:=TWritingSettingsForm.CreateForSettings(Settings);
  try Form.ShowModal; Settings:=Form.FSettings; Result:=True
  finally Form.Free end;
end;

end.
