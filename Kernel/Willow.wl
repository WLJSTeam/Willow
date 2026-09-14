BeginPackage["Willow`"];

ImagesToPDF::usage =
  "ImagesToPDF[file, image] or ImagesToPDF[file, {image1, ...}] writes one image per PDF page using the native Willow backend.";
ExportImagesToPDF::usage =
  "ExportImagesToPDF[file, images, resolution] is a compatibility wrapper for ImagesToPDF.";
PDFMerge::usage =
  "PDFMerge[file, {pdf1, pdf2, ...}] copies all pages from the input PDFs into a new PDF.";
PDFExtractPages::usage =
  "PDFExtractPages[file, pdf, pages] creates a PDF containing the selected pages, preserving their order.";
PDFDeletePages::usage =
  "PDFDeletePages[file, pdf, pages] creates a PDF with the selected pages removed.";
PDFPageCount::usage =
  "PDFPageCount[pdf] returns the number of pages using the native Willow backend.";
PDFToImages::usage =
  "PDFToImages[pdf, pages] rasterizes PDF pages. This operation currently uses the Wolfram PDF importer.";
WillowInformation::usage =
  "WillowInformation[] returns backend and platform information for Willow.";

ImagesToPDF::arg = "Expected an Image or a nonempty list of Image objects.";
ImagesToPDF::res = "ImageResolution must be a positive number; received `1`.";
PDFMerge::arg = "Expected a nonempty list of PDF filenames.";
PDFExtractPages::pages = "`1` is not a valid page selection for a `2`-page PDF.";
PDFDeletePages::pages = PDFExtractPages::pages;
PDFToImages::pages = PDFExtractPages::pages;
Willow::nolib = "The Willow native library was not found for `1`. Run build.wls with wolframscript on this platform.";
Willow::native = "The native PDF operation failed: `1`";
Willow::file = "The file `1` does not exist.";
Willow::write = "Could not atomically install the output file `1`.";

Options[ImagesToPDF] = {ImageResolution -> 360};
Options[PDFToImages] = {ImageResolution -> 144};

Begin["`Private`"];

$packageRoot = DirectoryName[DirectoryName[$InputFileName]];
$library = Missing["NotLoaded"];
$functions = <||>;

libraryFile[] := Module[{directory, candidates},
  directory = FileNameJoin[{$packageRoot, "LibraryResources", $SystemID}];
  candidates = FileNames["willow." <> Internal`DynamicLibraryExtension[], directory];
  If[Length[candidates] == 1, First[candidates], Missing["NotFound"]]
];

loadNative[] := Module[{file},
  If[AssociationQ[$functions] && Length[$functions] > 0, Return[True]];
  file = libraryFile[];
  If[MissingQ[file], Message[Willow::nolib, $SystemID]; Return[False]];
  $library = file;
  $functions = Quiet @ Check[
    <|
      "Open" -> LibraryFunctionLoad[file, "willowWriterOpen", {"UTF8String"}, Integer],
      "Close" -> LibraryFunctionLoad[file, "willowWriterClose", {Integer}, Integer],
      "AddImage" -> LibraryFunctionLoad[
        file, "willowWriterAddImage",
        {Integer, {LibraryDataType[Image], "Constant"}, Real}, Integer
      ],
      "AddPages" -> LibraryFunctionLoad[
        file, "willowWriterAddPages",
        {Integer, "UTF8String", {Integer, 1, "Constant"}}, Integer
      ],
      "PageCount" -> LibraryFunctionLoad[file, "willowPageCount", {"UTF8String"}, Integer],
      "LastError" -> LibraryFunctionLoad[file, "willowLastError", {}, "UTF8String"]
    |>,
    <||>
  ];
  If[Length[$functions] == 0, Message[Willow::nolib, $SystemID]; False, True]
];

lastError[] := Quiet @ Check[
  With[{error = $functions["LastError"][]}, If[StringQ[error] && error =!= "", error, "unspecified native error"]],
  "unspecified native error"
];

absoluteFile[file_String] := ExpandFileName[file];

existingFile[file_String] := Module[{path = absoluteFile[file]},
  If[FileExistsQ[path], path, Message[Willow::file, file]; $Failed]
];

temporaryOutput[file_String] := Module[{path = absoluteFile[file], directory},
  directory = DirectoryName[path];
  If[!DirectoryQ[directory], CreateDirectory[directory, CreateIntermediateDirectories -> True]];
  FileNameJoin[{directory, "." <> FileBaseName[path] <> "-" <> CreateUUID[] <> ".pdf"}]
];

withWriter[file_String, operation_] := Module[
  {output = absoluteFile[file], temporary, writer = -1, operationOK = False,
   closeOK = False, value},
  If[!loadNative[], Return[$Failed]];
  temporary = temporaryOutput[output];
  writer = $functions["Open"][temporary];
  If[writer < 1, Message[Willow::native, lastError[]]; Return[$Failed]];
  value = CheckAbort[
    Quiet @ Check[operation[writer], $Failed],
    Quiet[$functions["Close"][writer]];
    If[FileExistsQ[temporary], Quiet[DeleteFile[temporary]]];
    Abort[]
  ];
  operationOK = value =!= $Failed;
  closeOK = $functions["Close"][writer] == 0;
  If[operationOK && closeOK,
    Quiet @ Check[
      RenameFile[temporary, output, OverwriteTarget -> True];
      output,
      Message[Willow::write, output];
      If[FileExistsQ[temporary], Quiet[DeleteFile[temporary]]];
      $Failed
    ],
    Message[Willow::native, lastError[]];
    If[FileExistsQ[temporary], Quiet[DeleteFile[temporary]]];
    $Failed
  ]
];

pageCount[path_String] := Module[{count},
  If[!loadNative[], Return[$Failed]];
  count = $functions["PageCount"][path];
  If[count >= 0, count, Message[Willow::native, lastError[]]; $Failed]
];

resolvePageNumber[number_Integer, count_Integer] :=
  If[number < 0, count + number + 1, number];

resolvePages[spec_, count_Integer] := Module[{pages},
  pages = Which[
    spec === All, Range[count],
    IntegerQ[spec], {resolvePageNumber[spec, count]},
    MatchQ[spec, _Span], Quiet @ Check[Range[count][[spec]], $Failed],
    ListQ[spec] && AllTrue[spec, IntegerQ], resolvePageNumber[#, count] & /@ spec,
    True, $Failed
  ];
  If[pages === $Failed || !AllTrue[pages, 1 <= # <= count &], $Failed, pages]
];

nativeAppendPages[writer_Integer, path_String, pages_List] :=
  If[$functions["AddPages"][writer, path, pages] == 0, True, $Failed];

ImagesToPDF[file_String, image_Image, options : OptionsPattern[]] :=
  ImagesToPDF[file, {image}, options];

ImagesToPDF[file_String, images_List, OptionsPattern[]] := Module[
  {resolution = OptionValue[ImageResolution], prepared},
  If[images === {} || !AllTrue[images, MatchQ[_Image]], Message[ImagesToPDF::arg]; Return[$Failed]];
  If[!NumericQ[resolution] || !TrueQ[resolution > 0], Message[ImagesToPDF::res, resolution]; Return[$Failed]];
  prepared = Image[ColorConvert[#, "RGB"], "Byte"] & /@ images;
  withWriter[file, Function[writer,
    If[AllTrue[prepared, $functions["AddImage"][writer, #, N[resolution]] == 0 &], True, $Failed]
  ]]
];

ImagesToPDF[___] := (Message[ImagesToPDF::arg]; $Failed);

ExportImagesToPDF[file_String, images_, resolution_: 360] :=
  ImagesToPDF[file, images, ImageResolution -> resolution];

PDFPageCount[file_String] := Module[{path = existingFile[file]},
  If[path === $Failed, $Failed, pageCount[path]]
];

PDFMerge[file_String, inputs_List] := Module[{paths, counts},
  If[inputs === {} || !AllTrue[inputs, StringQ], Message[PDFMerge::arg]; Return[$Failed]];
  paths = existingFile /@ inputs;
  If[MemberQ[paths, $Failed], Return[$Failed]];
  counts = pageCount /@ paths;
  If[MemberQ[counts, $Failed], Return[$Failed]];
  withWriter[file, Function[writer,
    If[And @@ MapThread[nativeAppendPages[writer, #1, Range[#2]] &, {paths, counts}], True, $Failed]
  ]]
];

PDFMerge[___] := (Message[PDFMerge::arg]; $Failed);

PDFExtractPages[file_String, input_String, spec_: All] := Module[{path, count, pages},
  path = existingFile[input];
  If[path === $Failed, Return[$Failed]];
  count = pageCount[path];
  If[count === $Failed, Return[$Failed]];
  pages = resolvePages[spec, count];
  If[pages === $Failed, Message[PDFExtractPages::pages, spec, count]; Return[$Failed]];
  withWriter[file, Function[writer, nativeAppendPages[writer, path, pages]]]
];

PDFDeletePages[file_String, input_String, spec_] := Module[{path, count, deleted, kept},
  path = existingFile[input];
  If[path === $Failed, Return[$Failed]];
  count = pageCount[path];
  If[count === $Failed, Return[$Failed]];
  deleted = resolvePages[spec, count];
  If[deleted === $Failed, Message[PDFDeletePages::pages, spec, count]; Return[$Failed]];
  kept = Select[Range[count], !MemberQ[deleted, #] &];
  withWriter[file, Function[writer, nativeAppendPages[writer, path, kept]]]
];

PDFToImages[input_String, spec_: All, OptionsPattern[]] := Module[
  {path, count, pages, resolution = OptionValue[ImageResolution], images},
  path = existingFile[input];
  If[path === $Failed, Return[$Failed]];
  count = PDFPageCount[path];
  If[count === $Failed, Return[$Failed]];
  pages = resolvePages[spec, count];
  If[pages === $Failed, Message[PDFToImages::pages, spec, count]; Return[$Failed]];
  If[!NumericQ[resolution] || !TrueQ[resolution > 0], Message[ImagesToPDF::res, resolution]; Return[$Failed]];
  images = Quiet @ Check[
    Import[path, {"PageImages", pages}, ImageResolution -> resolution],
    $Failed
  ];
  If[IntegerQ[spec] && ListQ[images] && Length[images] == 1, First[images], images]
];

WillowInformation[] := <|
  "Version" -> "0.1.0",
  "SystemID" -> $SystemID,
  "NativeLibrary" -> libraryFile[],
  "PDFWriteAndEditBackend" -> "PDFio 1.6.4 (Apache-2.0)",
  "PDFRasterizationBackend" -> "Wolfram PDF importer"
|>;

End[];
EndPackage[];
