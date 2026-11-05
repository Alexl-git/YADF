unit YADF.Backup;

// Backup-before-overwrite shared by the YADF CLI (YadfMain) and the IDE wizard
// (YADFOT.Wizard): ONE naming/numbering/pruning scheme, so a mixed IDE + CLI
// workflow with BackupKeep never prunes the wrong sibling.

interface

type
  /// <summary>Receives a human-readable warning (no trailing newline) when a
  /// backup step fails non-fatally, e.g. an old backup could not be deleted.</summary>
  TBackupWarn = reference to procedure(const AMsg: string);

/// <summary>Copies AFile to a new backup (sibling .BCKn, or name.folderhash.stamp.bak
/// in ABackupDir, unique per source folder), then prunes this file's older backups beyond the newest AKeep.</summary>
/// <param name="AFile">The file about to be overwritten.</param>
/// <param name="ABackupDir">Backup folder; empty = next to AFile.</param>
/// <param name="AKeep">BackupKeep option; 0 keeps every backup.</param>
/// <param name="AOnWarn">Optional sink for a prune failure message (see PruneBackups); nil = silent.</param>
procedure BackupOriginalFile(const AFile: string; const ABackupDir: string; AKeep: Integer; const AOnWarn: TBackupWarn = nil);

implementation

uses
  System.SysUtils
  , System.Classes
  , System.IOUtils
  , System.Math
  , System.RegularExpressions
  ;

// Width the backup numbers are zero-padded to so that text order = numeric order.
const
  BACKUP_KEY_WIDTH = 20;

/// <summary>The sort key of AName when it is a backup YADF itself names for the
/// file ABase, else ''. Sibling form: ABase.BCKn (key = n). Folder form:
/// ABase.yyyymmdd-hhnnss[-n].bak (key = stamp + collision number), where ABase is
/// the folder-form base from FolderBackupBase (file name + source-folder hash).</summary>
/// <param name="AName">A file name (no path) found in the backup location.</param>
/// <param name="ABase">The file name (no path) whose backups are wanted.</param>
/// <param name="ASibling">True for the ABase.BCKn form, False for the .bak form.</param>
/// <returns>A key that sorts oldest-first as plain text, or '' for any other name.</returns>
/// <remarks>The match is anchored and ABase is escaped, so a different file's
/// backups (xABase..., ABase2...) can never match. Only names YADF writes match:
/// numbers have no leading zero and a collision number is 2 or more. An
/// old-format folder name (no folder hash) matches no ABase, so its owner is
/// ambiguous and it is never a candidate.</remarks>
function BackupSortKey(const AName, ABase: string; ASibling: Boolean): string;
var
  M: TMatch;
begin
  Result:= '';
  if ASibling then
  begin
    M:= TRegEx.Match(AName, '^' + TRegEx.Escape(ABase) + '\.BCK([1-9]\d*)$', [roIgnoreCase]);
    if M.Success then
      Result:= M.Groups[1].Value.PadLeft(BACKUP_KEY_WIDTH, '0');
  end
  else
  begin
    M:= TRegEx.Match(AName, '^' + TRegEx.Escape(ABase) + '\.(\d{8}-\d{6})(?:-([2-9]|[1-9]\d+))?\.bak$', [roIgnoreCase]);
    if M.Success then
      Result:= M.Groups[1].Value + '|' + (if (M.Groups.Count > 2) and (M.Groups[2].Value <> '') then M.Groups[2].Value else '1').PadLeft(BACKUP_KEY_WIDTH, '0');
  end;
end; // function

/// <summary>The base name of AFile's backups in a backup folder: the file name,
/// then 8 hex digits identifying the source folder, so same-named files from
/// different folders never share backups.</summary>
/// <param name="AFile">The source file.</param>
/// <returns>name.hhhhhhhh, e.g. Unit1.pas.1A2B3C4D.</returns>
/// <remarks>The hash is FNV-1a over the upper-cased full source folder path
/// without a trailing separator; stable across runs and case-insensitive like
/// the file system.</remarks>
function FolderBackupBase(const AFile: string): string;
const
  FNV_OFFSET: UInt64  = $811C9DC5;
  FNV_PRIME : UInt64  = $01000193;
  FNV_MASK  : UInt64  = $FFFFFFFF;
  HASH_DIGITS         = 8;
var
  C: Char;
  H: UInt64;
  S: string;
begin
  S:= UpperCase(ExcludeTrailingPathDelimiter(ExtractFilePath(TPath.GetFullPath(AFile))));
  H:= FNV_OFFSET;
  for C in S do
    H:= ((H xor Ord(C)) * FNV_PRIME) and FNV_MASK;
  Result:= ExtractFileName(AFile) + '.' + IntToHex(H, HASH_DIGITS);
end;

/// <summary>The next free sibling backup path for AFile: AFile.BCKn with n one above the highest existing number.</summary>
/// <param name="AFile">The source file.</param>
/// <returns>Full path of the new sibling backup (not created).</returns>
/// <remarks>A freed lower number is never reused, so the numbers stay in age order even after BackupKeep pruned the old ones.</remarks>
function NextSiblingBackupName(const AFile: string): string;
var
  Base: string;
  Dir : string;
  F   : string;
  Key : string;
  n   : Integer;
  Top : Integer;
begin
  Dir := ExtractFilePath(AFile);
  Base:= ExtractFileName(AFile);
  // One above the highest existing number (never a freed lower one), so the
  // numbers stay in age order even after BackupKeep has pruned the old ones.
  Top:= 0;
  for F in TDirectory.GetFiles(if Dir = '' then '.' else Dir, Base + '.*') do
  begin
    Key:= BackupSortKey(ExtractFileName(F), Base, True);
    n:= StrToIntDef(Key, 0);
    if n > Top then
      Top:= n;
  end;
  Result:= TPath.Combine(Dir, Base + '.BCK' + IntToStr(Top + 1));
end;

/// <summary>Deletes the older backups of AFile beyond the newest AKeep.</summary>
/// <param name="AFile">The file that was just backed up.</param>
/// <param name="ABackupDir">The backup folder; empty = the siblings next to AFile.</param>
/// <param name="AKeep">How many backups to keep; 0 or less keeps all.</param>
/// <param name="AOnWarn">Optional sink for a delete failure message; nil = silent.</param>
/// <remarks>Only names BackupOriginalFile itself generates for this exact file
/// (same name AND same source folder, see FolderBackupBase) are candidates
/// (see BackupSortKey). Old-format folder names without a folder hash are left
/// alone. A backup that cannot be deleted is reported
/// to AOnWarn (when assigned) and left; it never fails the run.</remarks>
procedure PruneBackups(const AFile, ABackupDir: string; AKeep: Integer; const AOnWarn: TBackupWarn);
var
  Base : string     ;
  Dir  : string     ;
  F    : string     ;
  i    : Integer    ;
  Key  : string     ;
  Found: TStringList;
begin
  if AKeep <= 0 then
    Exit;
  Base:= if Trim(ABackupDir) = '' then ExtractFileName(AFile) else FolderBackupBase(AFile);
  Dir:= if Trim(ABackupDir) = '' then ExtractFilePath(AFile) else ABackupDir;
  Found:= TStringList.Create;
  try
    for F in TDirectory.GetFiles(if Dir = '' then '.' else Dir, Base + '.*') do
    begin
      Key:= BackupSortKey(ExtractFileName(F), Base, Trim(ABackupDir) = '');
      if Key <> '' then
        Found.Add(Key + #9 + F);
    end;
    Found.CaseSensitive:= True;
    Found.Sort;
    for i:= 0 to Found.Count - AKeep - 1 do
    try
      TFile.Delete(Copy(Found[i], Pos(#9, Found[i]) + 1, MaxInt));
    except
      on E: Exception do
        if Assigned(AOnWarn) then
          AOnWarn('backup prune failed: ' + Found[i] + ' (' + E.Message + ')');
    end;
  finally
    Found.Free;
  end;
end; // procedure

procedure BackupOriginalFile(const AFile: string; const ABackupDir: string; AKeep: Integer; const AOnWarn: TBackupWarn);
var
  Base  : string ;
  F     : string ;
  Key   : string ;
  Stamp : string ;
  Target: string ;
  n     : Integer;
begin
  if Trim(ABackupDir) = '' then
  begin
    Target:= NextSiblingBackupName(AFile);
    TFile.Copy(AFile, Target, True);
    PruneBackups(AFile, ABackupDir, AKeep, AOnWarn);
    Exit;
  end;
  if not TDirectory.Exists(ABackupDir) then
    TDirectory.CreateDirectory(ABackupDir);
  Base:= FolderBackupBase(AFile);
  Stamp:= FormatDateTime('yyyymmdd-hhnnss', Now);
  Target:= TPath.Combine(ABackupDir, Base + '.' + Stamp + '.bak');
  // Two inputs with the same basename in one second used to share this name
  // and the second Copy overwrote the first file's only backup. Never
  // overwrite: number the collision instead.
  // Number above every backup of this file made in this second, not just the
  // first free name: once BackupKeep pruned the unnumbered one, reusing its
  // name would file the NEWEST backup as the oldest and prune it at once.
  n:= 1;
  for F in TDirectory.GetFiles(ABackupDir, Base + '.' + Stamp + '*') do
  begin
    Key:= BackupSortKey(ExtractFileName(F), Base, False);
    if Key <> '' then
      n:= Max(n, StrToIntDef(Copy(Key, Pos('|', Key) + 1, MaxInt), 1));
  end;
  if n > 1 then
  begin
    Target:= TPath.Combine(ABackupDir, Base + '.' + Stamp + '-' + IntToStr(n + 1) + '.bak');
    Inc(n);
  end;
  while TFile.Exists(Target) do
  begin
    Inc(n);
    Target:= TPath.Combine(ABackupDir, Base + '.' + Stamp + '-' + IntToStr(n) + '.bak');
  end;
  TFile.Copy(AFile, Target, False);
  PruneBackups(AFile, ABackupDir, AKeep, AOnWarn);
end; // procedure

end.
