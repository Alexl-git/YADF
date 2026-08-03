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
  object pnlTopBar: TPanel
    Left = 0
    Top = 0
    Width = 1200
    Height = 36
    Align = alTop
    BevelOuter = bvNone
    TabOrder = 0
    object lblIniPath: TLabel
      Left = 318
      Top = 10
      Width = 18
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
  object dlgOpen: TOpenDialog
    Filter = 'INI files|*.ini|All files|*.*'
    Left = 200
    Top = 300
  end
  object dlgSaveIni: TSaveDialog
    DefaultExt = 'ini'
    Filter = 'INI files|*.ini|All files|*.*'
    Left = 260
    Top = 300
  end
end
