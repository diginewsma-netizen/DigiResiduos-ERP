object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'Form1'
  ClientHeight = 536
  ClientWidth = 1363
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  PixelsPerInch = 96
  TextHeight = 13
  object WebGMaps: TWebGMaps
    Left = 279
    Top = 8
    Width = 400
    Height = 250
    Clusters = <>
    Markers = <>
    Polylines = <
      item
        Polyline.Icons = <>
        Polyline.Path = <>
        Polyline.Zindex = 1
      end>
    Polygons = <>
    Directions = <>
    MapOptions.DefaultLatitude = 48.859040000000000000
    MapOptions.DefaultLongitude = 2.294297000000000000
    Routing.PolylineOptions.Icons = <>
    StreetViewOptions.DefaultLatitude = 48.859040000000000000
    StreetViewOptions.DefaultLongitude = 2.294297000000000000
    MapPersist.Location = mplInifile
    MapPersist.Key = 'WebGMaps'
    MapPersist.Section = 'MapBounds'
    PolygonLabel.Font.Charset = DEFAULT_CHARSET
    PolygonLabel.Font.Color = clBlack
    PolygonLabel.Font.Height = -16
    PolygonLabel.Font.Name = 'Arial'
    PolygonLabel.Font.Style = []
    TabOrder = 0
    Version = '2.9.4.8'
  end
  object Memo1: TMemo
    Left = 16
    Top = 8
    Width = 257
    Height = 250
    Lines.Strings = (
      'Memo1')
    TabOrder = 1
  end
  object Btn: TButton
    Left = 16
    Top = 264
    Width = 75
    Height = 25
    Caption = 'Btn'
    TabOrder = 2
  end
end
