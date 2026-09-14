#!/usr/bin/env wolframscript

root = DirectoryName[DirectoryName[$InputFileName]];
report = TestReport[FileNameJoin[{root, "Tests", "Willow.wlt"}]];
Print[report];
Exit[If[report["TestsFailedCount"] == 0, 0, 1]];
