unit of_object_types;

interface

type
  TNotifyEvent = procedure(Sender: TObject) of object;

  TThing = class
    FHandler: function(P1: Integer): HResult of object stdcall;
    procedure Run;
  end;

implementation

procedure TThing.Run;
begin
  WriteLn('ok');
end;

end.
