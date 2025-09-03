unit Unit1;

interface

{$WARN SYMBOL_PLATFORM OFF}

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Classes, System.JSON, System.NetEncoding,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.StdCtrls,
  REST.Client, REST.Types, UWebGMapsCommon, UWebGMaps;
  // Ajuste a(s) unit(s) do seu TMS VCL WebGMaps conforme sua instalação:
  // Em muitas instalações recentes é "WebGMaps"; em outras, "AdvWebGMaps".
  //WebGMaps; // <-- se a sua for AdvWebGMaps, troque aqui e no uses abaixo

type
  TLatLng = record
    Lat: Double;
    Lng: Double;
    class function Create(ALat, ALng: Double): TLatLng; static;
  end;

  TForm1 = class(TForm)
    WebGMaps: TWebGMaps;
    Memo1: TMemo;
    Btn: TButton;
    procedure FormCreate(Sender: TObject);
  private
    //FWebGMaps: TWebGMaps;
    //FMemo: TMemo;
    //FBtn: TButton;

    procedure BtnRotaClick(Sender: TObject);

    { Helpers }
    function LatLngToStr(const P: TLatLng): string;
    function DecodePolyline(const Encoded: string): TArray<TLatLng>;

    { REST (Directions API com waypoints=optimize:true) }
    procedure GetOptimizedRoute(const ApiKey: string; const P: array of TLatLng;
      out Ordered: TArray<TLatLng>; out WaypointOrder: TArray<Integer>;
      out OverviewPolyline: string);

    { Desenho no WebGMaps }
    procedure DrawMarkers(const Ordered: TArray<TLatLng>);
    procedure DrawRouteFromOverviewPolyline(const Encoded: string);
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.dfm}

{ ===== Util ===== }

class function TLatLng.Create(ALat, ALng: Double): TLatLng;
begin
  Result.Lat := ALat;
  Result.Lng := ALng;
end;

function TForm1.LatLngToStr(const P: TLatLng): string;
var
  fs: TFormatSettings;
begin
  fs := TFormatSettings.Create;
  fs.DecimalSeparator := '.';
  Result := Format('%.8f,%.8f', [P.Lat, P.Lng], fs);
end;

function TForm1.DecodePolyline(const Encoded: string): TArray<TLatLng>;
var
  idx, len, shift, result_, b, lat, lng, dlat, dlng: Integer;
begin
  idx := 1;
  len := Length(Encoded);
  lat := 0;
  lng := 0;
  SetLength(Result, 0);

  while idx <= len do
  begin
    // latitude
    shift := 0; result_ := 0;
    repeat
      b := Ord(Encoded[idx]) - 63; Inc(idx);
      result_ := result_ or ((b and $1F) shl shift);
      Inc(shift, 5);
    until b < $20;
    if (result_ and 1) <> 0 then dlat := -(result_ shr 1) else dlat := (result_ shr 1);
    lat := lat + dlat;

    // longitude
    shift := 0; result_ := 0;
    repeat
      b := Ord(Encoded[idx]) - 63; Inc(idx);
      result_ := result_ or ((b and $1F) shl shift);
      Inc(shift, 5);
    until b < $20;
    if (result_ and 1) <> 0 then dlng := -(result_ shr 1) else dlng := (result_ shr 1);
    lng := lng + dlng;

    SetLength(Result, Length(Result)+1);
    Result[High(Result)] := TLatLng.Create(lat/1e5, lng/1e5);
  end;
end;

{ ===== Chamada REST ao Directions API (waypoints=optimize:true) ===== }

procedure TForm1.GetOptimizedRoute(const ApiKey: string; const P: array of TLatLng;
  out Ordered: TArray<TLatLng>; out WaypointOrder: TArray<Integer>;
  out OverviewPolyline: string);
var
  Client: TRESTClient;
  Req: TRESTRequest;
  Resp: TRESTResponse;
  OriginStr, DestStr, WayStr, Url: string;
  I: Integer;
  JSON: TJSONObject;
  Routes: TJSONArray;
  RouteObj: TJSONObject;
  WPO: TJSONArray;
  Inter: TArray<TLatLng>;
begin
  if Length(P) <> 6 then
    raise Exception.Create('Use 6 pontos: P0 (origem), P1..P4 (visitas), P5 (retorno = P0).');

  OriginStr := LatLngToStr(P[0]);
  DestStr   := LatLngToStr(P[5]);

  SetLength(Inter, 4);
  for I := 1 to 4 do
    Inter[I-1] := P[I];

  WayStr := 'optimize:true';
  for I := 0 to High(Inter) do
    WayStr := WayStr + '|' + LatLngToStr(Inter[I]);

  Url :=
    'https://maps.googleapis.com/maps/api/directions/json?' +
    'origin=' + TNetEncoding.URL.Encode(OriginStr) + '&' +
    'destination=' + TNetEncoding.URL.Encode(DestStr) + '&' +
    'waypoints=' + TNetEncoding.URL.Encode(WayStr) + '&' +
    'units=metric&language=pt-BR&key=' + ApiKey;

  Client := TRESTClient.Create('');
  Req := TRESTRequest.Create(nil);
  Resp := TRESTResponse.Create(nil);
  try
    Req.Client := Client;
    Req.Response := Resp;
    Req.Method := rmGET;
    Req.Resource := Url;
    Req.Execute;

    if Resp.StatusCode <> 200 then
      raise Exception.CreateFmt('HTTP %d: %s', [Resp.StatusCode, Resp.StatusText]);

    JSON := TJSONObject.ParseJSONValue(Resp.Content) as TJSONObject;
    if JSON = nil then
      raise Exception.Create('Resposta JSON inválida.');

    try
      if JSON.GetValue<string>('status') <> 'OK' then
        raise Exception.Create('Directions falhou: ' + JSON.GetValue<string>('status'));

      Routes := JSON.GetValue<TJSONArray>('routes');
      if (Routes = nil) or (Routes.Count = 0) then
        raise Exception.Create('Nenhuma rota retornada.');

      RouteObj := Routes.Items[0] as TJSONObject;
      WPO := RouteObj.GetValue<TJSONArray>('waypoint_order');

      SetLength(WaypointOrder, WPO.Count);
      for I := 0 to WPO.Count - 1 do
        WaypointOrder[I] := WPO.Items[I].Value.ToInteger;

      // Reconstrói sequência final: origem + intermediários reordenados + retorno
      SetLength(Ordered, 0);
      SetLength(Ordered, Length(Ordered)+1);
      Ordered[High(Ordered)] := P[0];

      for I := 0 to High(WaypointOrder) do
      begin
        SetLength(Ordered, Length(Ordered)+1);
        Ordered[High(Ordered)] := Inter[WaypointOrder[I]];
      end;

      SetLength(Ordered, Length(Ordered)+1);
      Ordered[High(Ordered)] := P[5];

      // polyline geral (overview)
      OverviewPolyline := RouteObj.GetValue<TJSONObject>('overview_polyline')
                                   .GetValue<string>('points');
    finally
      JSON.Free;
    end;
  finally
    Req.Free;
    Resp.Free;
    Client.Free;
  end;
end;

{ ===== Desenho no TWebGMaps ===== }

procedure TForm1.DrawMarkers(const Ordered: TArray<TLatLng>);
var
  i: Integer;
begin
  if Length(Ordered) = 0 then Exit;

  // Centraliza no ponto inicial e limpa shapes anteriores
  WebGMaps.MapPanTo(Ordered[0].Lat, Ordered[0].Lng);
  WebGMaps.Markers.Clear;
  WebGMaps.Polylines.Clear;

  // Marcadores
  WebGMaps.Markers.Add(Ordered[0].Lat, Ordered[0].Lng, 'Origem/Destino');

  for i := 1 to High(Ordered)-1 do
    WebGMaps.Markers.Add(Ordered[i].Lat, Ordered[i].Lng, Format('P%d', [i]));

  WebGMaps.Markers.Add(Ordered[High(Ordered)].Lat, Ordered[High(Ordered)].Lng, 'Retorno');
end;

procedure TForm1.DrawRouteFromOverviewPolyline(const Encoded: string);
var
  pts: TArray<TLatLng>;
  i, idx: Integer;
begin
  if Encoded = '' then Exit;

  pts := DecodePolyline(Encoded);
  if Length(pts) = 0 then Exit;

  // Limpa polylines anteriores
  WebGMaps.Polylines.Clear;


  // Cria polyline e adiciona os pontos
  // Em muitas versões existe PolylinesAdd/Polylines[index].AddPoint:
  idx := WebGMaps.PolylinesAdd;
  for i := 0 to High(pts) do
    WebGMaps.Polylines[idx].AddPoint(pts[i].Lat, pts[i].Lng);

  // Dica: se a sua versão não tiver PolylinesAdd, use algo como:
  //   idx := FWebGMaps.Polylines.Add;
  //   FWebGMaps.Polylines.Items[idx].AddPoint(...);
  // Ajuste os nomes mantendo a mesma lógica.
end;

{ ===== UI / Fluxo ===== }

procedure TForm1.FormCreate(Sender: TObject);
begin
  Caption := 'Roteiro bate-volta (origem + 4 pontos + retorno) - TWebGMaps + Directions API';
  Width := 1000;
  Height := 700;

  // Cria componentes em runtime (sem DFM)
  WebGMaps := TWebGMaps.Create(Self);
  WebGMaps.Parent := Self;
  WebGMaps.Align := alClient;

  // Defina sua API key do Google (Maps/JS e Directions habilitados)
  WebGMaps.APIKey := 'SUA_API_KEY_AQUI'; // <-- SUBSTITUA

  Memo1 := TMemo.Create(Self);
  Memo1.Parent := Self;
  Memo1.Align := alBottom;
  Memo1.ScrollBars := ssBoth;
  Memo1.Height := 180;
  Memo1.WordWrap := False;

  Btn := TButton.Create(Self);
  Btn.Parent := Self;
  Btn.Caption := 'Montar rota (bate-volta)';
  Btn.Align := alTop;
  Btn.Height := 32;
  Btn.OnClick := BtnRotaClick;
end;

procedure TForm1.BtnRotaClick(Sender: TObject);
var
  P: array[0..5] of TLatLng; // P0 origem, P1..P4 visitas, P5 = P0 (retorno)
  Ordered: TArray<TLatLng>;
  OrderIdx: TArray<Integer>;
  Poly: string;
  i: Integer;
  ApiKey: string;
begin
  Memo.Clear;

  // ======= Defina seus pontos =======
  P[0] := TLatLng.Create(-23.561684, -46.625378); // origem
  P[1] := TLatLng.Create(-23.550520, -46.633308);
  P[2] := TLatLng.Create(-23.559616, -46.658217);
  P[3] := TLatLng.Create(-23.566932, -46.651451);
  P[4] := TLatLng.Create(-23.573300, -46.641700);
  P[5] := P[0]; // retorno (bate-volta)
  // ===================================

  ApiKey := 'SUA_API_KEY_AQUI'; // <-- SUBSTITUA (Directions API habilitado)

  try
    // 1) Pede otimização na Google Directions API
    GetOptimizedRoute(ApiKey, P, Ordered, OrderIdx, Poly);

    // 2) Mostra a ordem retornada (índices referem-se a P[1..4])
    Memo1.Lines.Add('Ordem dos 4 intermediários (indices referem-se a P[1..4]):');
    for i := 0 to High(OrderIdx) do
      Memo1.Lines.Add(Format('%d', [OrderIdx[i]]));

    // 3) Desenha markers no componente
    DrawMarkers(Ordered);

    // 4) Desenha a rota decodificando a overview_polyline (sem usar GetDirections)
    DrawRouteFromOverviewPolyline(Poly);

  except
    on E: Exception do
    begin
      Memo1.Lines.Add('ERRO: ' + E.Message);
      Application.MessageBox(PChar('Erro ao montar a rota: ' + E.Message),
                             'Erro', MB_ICONERROR or MB_OK);
    end;
  end;
end;

end.


