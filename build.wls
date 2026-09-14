#!/usr/bin/env wolframscript

root = DirectoryName[$InputFileName];
sourceRoot = FileNameJoin[{root, "LibraryResources", "Source"}];
pdfioRoot = FileNameJoin[{sourceRoot, "vendor", "pdfio"}];
zlibRoot = FileNameJoin[{sourceRoot, "vendor", "zlib"}];
target = FileNameJoin[{root, "LibraryResources", $SystemID}];

Needs["CCompilerDriver`"];

If[!DirectoryQ[target], CreateDirectory[target, CreateIntermediateDirectories -> True]];

pdfioSources = Join[FileNames["pdfio-*.c", pdfioRoot], {FileNameJoin[{pdfioRoot, "ttf.c"}]}];
zlibSources = FileNameJoin[{zlibRoot, #}] & /@ {
  "adler32.c", "compress.c", "crc32.c", "deflate.c", "infback.c",
  "inffast.c", "inflate.c", "inftrees.c", "trees.c", "uncompr.c", "zutil.c"
};

library = CreateLibrary[
  Join[{FileNameJoin[{sourceRoot, "willow.c"}]}, pdfioSources, zlibSources],
  "willow",
  "TargetDirectory" -> target,
  "IncludeDirectories" -> {pdfioRoot, zlibRoot},
  "CompileOptions" -> If[$OperatingSystem === "Windows", {"/O2"}, {"-O3", "-fvisibility=hidden"}],
  "ShellOutputFunction" -> Print
];

If[library === $Failed, Exit[1]];
Print[library];
