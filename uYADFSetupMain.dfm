object frmMain: TfrmMain
  Left = 0
  Top = 0
  Caption = 'YADFSetup'
  ClientHeight = 640
  ClientWidth = 1200
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  Position = poScreenCenter
  OnCreate = FormCreate
  TextHeight = 15
  object splLeft: TSplitter
    Left = 360
    Top = 0
    Height = 640
    ExplicitLeft = 360
    ExplicitHeight = 640
  end
  object splRight: TSplitter
    Left = 780
    Top = 0
    Height = 640
    ExplicitLeft = 780
    ExplicitHeight = 640
  end
  object pnlSettings: TPanel
    Left = 0
    Top = 0
    Width = 360
    Height = 640
    Align = alLeft
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 0
    object pnlSettingsBar: TPanel
      Left = 0
      Top = 0
      Width = 360
      Height = 56
      Align = alTop
      BevelOuter = bvNone
      Caption = ''
      TabOrder = 0
      object lblIniPath: TLabel
        Left = 6
        Top = 36
        Width = 16
        Height = 15
        Caption = 'INI:'
      end
      object btnLoadSettings: TButton
        Left = 6
        Top = 6
        Width = 96
        Height = 25
        Caption = 'Load Settings'
        TabOrder = 0
        OnClick = btnLoadSettingsClick
      end
      object btnSaveSettings: TButton
        Left = 108
        Top = 6
        Width = 96
        Height = 25
        Caption = 'Save As...'
        TabOrder = 1
        OnClick = btnSaveSettingsClick
      end
      object btnReset: TButton
        Left = 210
        Top = 6
        Width = 96
        Height = 25
        Caption = 'Reset'
        TabOrder = 2
        OnClick = btnResetClick
      end
    end
    object pnlProfiles: TPanel
      Left = 0
      Top = 56
      Width = 360
      Height = 180
      Align = alTop
      BevelOuter = bvNone
      Caption = ''
      TabOrder = 2
      object lblProfHdr: TLabel
        Left = 6
        Top = 4
        Width = 320
        Height = 15
        Caption = 'Profiles  -  which yadf.ini each IDE shortcut uses'
        Font.Charset = DEFAULT_CHARSET
        Font.Color = clWindowText
        Font.Height = -12
        Font.Name = 'Segoe UI'
        Font.Style = [fsBold]
        ParentFont = False
      end
      object lblProfHelp1: TLabel
        Left = 6
        Top = 22
        Width = 348
        Height = 15
        Caption = 'Click a file, then press  F  or  R  to assign it.   Del = unassign'
      end
      object lblProfHelp2: TLabel
        Left = 6
        Top = 38
        Width = 348
        Height = 15
        Caption = 'F = Ctrl+Shift+Alt+F  (YADF.exe default; or  YADF.exe --ini <file>)'
      end
      object lblProfHelp3: TLabel
        Left = 6
        Top = 54
        Width = 348
        Height = 15
        Caption = 'R = Ctrl+Shift+Alt+R  (YADFOT only)'
      end
      object lstProfiles: TListBox
        Left = 6
        Top = 74
        Width = 348
        Height = 70
        Anchors = [akLeft, akTop, akRight, akBottom]
        ItemHeight = 15
        TabOrder = 0
        OnClick = lstProfilesClick
        OnKeyDown = lstProfilesKeyDown
      end
      object lblEditing: TLabel
        Left = 6
        Top = 152
        Width = 230
        Height = 15
        Anchors = [akLeft, akBottom]
        Caption = 'Editing: yadf.ini'
      end
      object btnNewProfile: TButton
        Left = 250
        Top = 148
        Width = 104
        Height = 25
        Anchors = [akRight, akBottom]
        Caption = 'New profile...'
        TabOrder = 1
        OnClick = btnNewProfileClick
      end
    end
    object splProfiles: TSplitter
      Left = 0
      Top = 236
      Width = 360
      Height = 4
      Cursor = crVSplit
      Align = alTop
      ExplicitTop = 236
    end
    object sbSettings: TScrollBox
      Left = 0
      Top = 240
      Width = 360
      Height = 400
      Align = alClient
      BorderStyle = bsNone
      TabOrder = 1
    end
  end
  object pnlSource: TPanel
    Left = 363
    Top = 0
    Width = 417
    Height = 640
    Align = alLeft
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 1
    object pnlSourceBar: TPanel
      Left = 0
      Top = 0
      Width = 417
      Height = 32
      Align = alTop
      BevelOuter = bvNone
      Caption = ''
      TabOrder = 0
      object lblSourceFile: TLabel
        Left = 110
        Top = 9
        Width = 19
        Height = 15
        Caption = 'file:'
      end
      object btnOpenSource: TButton
        Left = 6
        Top = 4
        Width = 96
        Height = 25
        Caption = 'Open File...'
        TabOrder = 0
        OnClick = btnOpenSourceClick
      end
    end
    object memSource: TMemo
      Left = 0
      Top = 32
      Width = 417
      Height = 608
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      ScrollBars = ssBoth
      TabOrder = 1
      WordWrap = False
      OnChange = memSourceChange
    end
  end
  object pnlResult: TPanel
    Left = 783
    Top = 0
    Width = 417
    Height = 640
    Align = alClient
    BevelOuter = bvNone
    Caption = ''
    TabOrder = 2
    object pnlResultBar: TPanel
      Left = 0
      Top = 0
      Width = 417
      Height = 32
      Align = alTop
      BevelOuter = bvNone
      Caption = ''
      TabOrder = 0
      object lblResultStatus: TLabel
        Left = 110
        Top = 9
        Width = 14
        Height = 15
        Caption = 'OK'
      end
      object btnCopy: TButton
        Left = 6
        Top = 4
        Width = 96
        Height = 25
        Caption = 'Copy'
        TabOrder = 0
        OnClick = btnCopyClick
      end
    end
    object memResult: TMemo
      Left = 0
      Top = 32
      Width = 417
      Height = 608
      Align = alClient
      Font.Charset = DEFAULT_CHARSET
      Font.Color = clWindowText
      Font.Height = -13
      Font.Name = 'Consolas'
      Font.Style = []
      ParentFont = False
      ReadOnly = True
      ScrollBars = ssBoth
      TabOrder = 1
      WordWrap = False
    end
  end
  object dlgOpen: TOpenDialog
    Filter = 'Pascal/INI|*.pas;*.dpr;*.inc;*.ini|All files|*.*'
    Left = 200
    Top = 300
  end
  object dlgSaveIni: TSaveDialog
    DefaultExt = 'ini'
    Filter = 'INI files|*.ini|All files|*.*'
    Left = 260
    Top = 300
  end
  object tmrReformat: TTimer
    Enabled = False
    Interval = 300
    OnTimer = tmrReformatTimer
    Left = 320
    Top = 300
  end
end
