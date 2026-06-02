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
    object sbSettings: TScrollBox
      Left = 0
      Top = 56
      Width = 360
      Height = 584
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
