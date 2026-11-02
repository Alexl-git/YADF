unit idem_label_collapse;

// Task 10 mechanism D (packed profile): a stale block-end label from an earlier
// format kept CollapseShortBlocks from folding the block, then the label was
// dropped as too short; the next format folded it.

interface

procedure Spin(DChan, ET: Integer);

implementation

uses
  System.Classes
  , System.SysUtils
  ;

type
  Application = class
    class procedure ProcessMessages;
  end;
  TPortObj = class
    procedure ProcessCommunications;
  end;
  TGage = record
    GagePort: TPortObj;
    LineBuf: TStringList;
  end;

var
  GagePort: array[0..3] of TGage;

class procedure Application.ProcessMessages;
begin
end;

procedure TPortObj.ProcessCommunications;
begin
end;

function TimerExpired(AET: Integer): Boolean;
begin
  Result:= AET > 0;
end;

procedure Spin(DChan, ET: Integer);
begin
  begin
    while (not TimerExpired(ET)) and (GagePort[DChan].LineBuf.Count <= 0) do
    begin
      Application.ProcessMessages;
      GagePort[DChan].GagePort.ProcessCommunications;
      Sleep(0);
    end; // while
    GagePort[DChan].LineBuf.Add('READ');
  end;
end;

end.