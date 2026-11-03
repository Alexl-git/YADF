unit review1102_l2d_trailing_op;
// REVIEW-2026-11-02 corruption L2d: an over-long line ending in a binary
// operator, continued by hand on the next line, kept the trailing "+" and the
// next format joined the two lines.
interface
function GetErrorData(ACount: Integer): string;
implementation
uses System.SysUtils;
function GetErrorData(ACount: Integer): string;
var
	i: Integer;
begin
	Result:= #10#13;
	for i := 0 to ACount - 1 do
	begin
		Result:= Result + #10#13 + '       Error Code: ' + IntToStr(ACount * 1000) + '  Category: ' + IntToStr(ACount * 2000) + '  Subcode of the error: ' + IntToStr(ACount + 3000 * i) +
			'  Native Code: ' + IntToStr(ACount + 4000);
	end;
end;
end.