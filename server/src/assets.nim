import std/[os, times, algorithm, tables]

import protocol

type
  AssetStore* = object
    manifest*: seq[AssetEntry]
    paths*: Table[uint16, string]

proc assetModifiedMs(path: string): uint64 =
  let modified = getLastModificationTime(path)
  result = uint64(toUnix(modified)) * 1000'u64

proc loadAssets*(directory: string): AssetStore =
  createDir(directory)

  var paths: seq[string] = @[]
  for path in walkDirRec(directory):
    if fileExists(path):
      paths.add(path)
  paths.sort(system.cmp[string])

  var nextId: uint16 = 1
  for path in paths:
    let sizeBytes = getFileSize(path)
    let entry = AssetEntry(
      assetId: nextId,
      assetType: 1'u8,
      modTime: assetModifiedMs(path),
      sizeBytes: uint32(sizeBytes),
      path: path
    )
    result.manifest.add(entry)
    result.paths[nextId] = path
    inc(nextId)

proc readAssetPayload*(store: AssetStore, entry: AssetEntry): string =
  readFile(entry.path)
