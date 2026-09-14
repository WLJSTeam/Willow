root = DirectoryName[DirectoryName[$InputFileName]];
PacletDirectoryLoad[root];
Needs["Willow`"];

testDirectory = CreateDirectory[];
testFile[name_] := FileNameJoin[{testDirectory, name}];

red = Image[ConstantArray[{1., 0., 0.}, {16, 24}], "Real"];
green = Image[ConstantArray[{0., 1., 0.}, {12, 20}], "Real"];
blue = Image[ConstantArray[{0., 0., 1.}, {10, 18}], "Real"];
yellow = Image[ConstantArray[{1., 1., 0.}, {8, 14}], "Real"];

meanRGB[image_Image] := Round[255 Mean[Flatten[ImageData[RemoveAlphaChannel[image]], 1]]];
pageColors[file_] := meanRGB /@ Willow`PDFToImages[file, All, ImageResolution -> 72];

VerificationTest[
  FileExistsQ[Willow`ImagesToPDF[testFile["images.pdf"], {red, green}, ImageResolution -> 72]],
  True,
  TestID -> "write-image-list"
]

VerificationTest[
  Willow`PDFPageCount[testFile["images.pdf"]],
  2,
  TestID -> "native-page-count"
]

VerificationTest[
  {Willow`ExportImagesToPDF[testFile["compat.pdf"], red, 72],
   Willow`PDFPageCount[testFile["compat.pdf"]]}[[2]],
  1,
  TestID -> "original-helper-compatible-form"
]

VerificationTest[
  ImageDimensions /@ Willow`PDFToImages[testFile["images.pdf"], All, ImageResolution -> 72],
  {{24, 16}, {20, 12}},
  TestID -> "round-trip-page-dimensions"
]

Willow`ImagesToPDF[testFile["more.pdf"], {blue, yellow}, ImageResolution -> 72];

VerificationTest[
  {Willow`PDFMerge[testFile["merged.pdf"], {testFile["images.pdf"], testFile["more.pdf"]}],
   Willow`PDFPageCount[testFile["merged.pdf"]]}[[2]],
  4,
  TestID -> "merge-pdfs"
]

VerificationTest[
  pageColors[testFile["merged.pdf"]],
  {{255, 0, 0}, {0, 255, 0}, {0, 0, 255}, {255, 255, 0}},
  TestID -> "merge-preserves-order"
]

Willow`PDFExtractPages[testFile["extract.pdf"], testFile["merged.pdf"], {4, 2}];

VerificationTest[
  {Willow`PDFPageCount[testFile["extract.pdf"]], pageColors[testFile["extract.pdf"]]},
  {2, {{255, 255, 0}, {0, 255, 0}}},
  TestID -> "extract-and-reorder-pages"
]

Willow`PDFDeletePages[testFile["delete.pdf"], testFile["merged.pdf"], {2, 4}];

VerificationTest[
  {Willow`PDFPageCount[testFile["delete.pdf"]], pageColors[testFile["delete.pdf"]]},
  {2, {{255, 0, 0}, {0, 0, 255}}},
  TestID -> "delete-pages"
]

Willow`PDFExtractPages[testFile["last.pdf"], testFile["merged.pdf"], -1];

VerificationTest[
  pageColors[testFile["last.pdf"]],
  {{255, 255, 0}},
  TestID -> "negative-page-index"
]

VerificationTest[
  Head[Willow`PDFToImages[testFile["merged.pdf"], 1, ImageResolution -> 72]],
  Image,
  TestID -> "scalar-page-rasterization"
]

VerificationTest[
  Quiet[Willow`PDFExtractPages[testFile["invalid.pdf"], testFile["merged.pdf"], 99]],
  $Failed,
  TestID -> "reject-invalid-page"
]

DeleteDirectory[testDirectory, DeleteContents -> True];
