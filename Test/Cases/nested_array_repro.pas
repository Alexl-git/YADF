unit nested_array_repro;

interface

implementation

procedure Foo;
const
	Explane: array[0..1, 0..5] of String = (
	(
	'Ppk > 2.00',
	'Ppk: 1.67 - 2.00',
	'Ppk: 1.33 - 1.67',
	'Ppk: 1 - 1.33',
	'Ppk < 1.00',
	'??'
	),
	(
	'Defects are extremely improbable',
	'Defects are reasonably improbable',
	'Remote probability of defects',
	'Defects are reasonably probable',
	'High risk of defects',
	'??'
	)
	);
begin
end;

end.
