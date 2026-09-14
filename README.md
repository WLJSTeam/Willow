# Willow

Willow is a small Wolfram Language source package for PDF operations that are awkward or slow with the built-in PDF exporter. Its write/edit path runs in the kernel process through LibraryLink — __there is no Python session and no per-call external process__.

The native core uses [PDFio](https://github.com/michaelrsweet/pdfio) 1.6.4 and zlib 1.3.1. Both are vendored and compiled into one platform library, so the resulting binary has no non-system runtime dependency.

## Current API

```wl
PacletDirectoryLoad["/path/to/willow"];
Needs["Willow`"];

ImagesToPDF["scan.pdf", image, ImageResolution -> 360]
ImagesToPDF["album.pdf", {image1, image2, image3}, ImageResolution -> 360]

(* Drop-in form matching the original helper *)
ExportImagesToPDF["album.pdf", {image1, image2, image3}, 360]

PDFMerge["joined.pdf", {"one.pdf", "two.pdf"}]
PDFExtractPages["selection.pdf", "joined.pdf", {5, 1, 3}]
PDFDeletePages["without-appendix.pdf", "joined.pdf", 10 ;; 14]
PDFPageCount["joined.pdf"]

PDFToImages["joined.pdf", All, ImageResolution -> 144]
PDFToImages["joined.pdf", 2, ImageResolution -> 144]
```

Page selections accept `All`, a page number, a `Span`, or a list of page numbers. Negative integers count from the end. Extraction preserves duplicates and ordering. Operations write to a sibling temporary file and rename it into place only after the native writer closes successfully.

`ImagesToPDF` uses direct `MImage` access. Every image becomes a full-bleed page whose physical dimensions are derived from its pixel dimensions and `ImageResolution`. RGB, grayscale, bit, byte, real, and alpha-channel input images are normalized to interleaved 8-bit RGB before entering the native writer.

## Build (if needed)

Requirements are a local Wolfram installation and the normal C compiler for the platform:

- macOS: Xcode command-line tools
- Linux: GCC or Clang development tools
- Windows: a Visual Studio C/C++ toolchain supported by Wolfram's `CCompilerDriver`` package

From the repository root:

```sh
wolframscript -file build.wls
wolframscript -file Tests/run.wls
```

The build script places the result in `LibraryResources/$SystemID/`, the conventional cross-platform LibraryLink layout. Build once on each target operating system/architecture and include those directories in the development directory. Load it directly with `PacletDirectoryLoad`; no `.paclet` archive is created.

## Rasterization boundary

PDFio reads, writes, and copies PDF object graphs but deliberately does not render pages. Accordingly, `PDFToImages` currently delegates only rasterization to WL's `Import[..., {"PageImages", ...}]`; all page counting, image PDF creation, merging, extraction, and deletion use the native PDFio LibraryLink backend. `WillowInformation[]` reports both backends explicitly.

A fully native `PDFToImages` implementation needs a renderer such as PDFium (permissive, but large and difficult to build) or MuPDF (compact, but AGPL/commercially licensed). Keeping that choice optional avoids imposing a large binary or a reciprocal license on the core package.

## Licensing

Willow is Apache-2.0. Vendored PDFio is Apache-2.0 and vendored zlib uses the zlib license; their license files are retained under `LibraryResources/Source/vendor/`.
