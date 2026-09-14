#include "WolframLibrary.h"
#include "WolframImageLibrary.h"
#include "pdfio.h"
#include "pdfio-content.h"

#include <stdio.h>
#include <string.h>

#define WILLOW_MAX_WRITERS 32
#define WILLOW_ERROR_SIZE 1024

typedef struct {
  pdfio_file_t *pdf;
} willow_writer_t;

static willow_writer_t g_writers[WILLOW_MAX_WRITERS];
static char g_last_error[WILLOW_ERROR_SIZE] = "";

static void set_error(const char *message) {
  if (!message) message = "Unknown PDF error.";
  snprintf(g_last_error, sizeof(g_last_error), "%s", message);
}

static bool pdf_error(pdfio_file_t *pdf, const char *message, void *data) {
  (void)pdf;
  (void)data;
  set_error(message);
  return true;
}

static willow_writer_t *writer_for_id(mint id) {
  if (id < 1 || id > WILLOW_MAX_WRITERS) return NULL;
  if (!g_writers[id - 1].pdf) return NULL;
  return g_writers + id - 1;
}

DLLEXPORT mint WolframLibrary_getVersion(void) {
  return WolframLibraryVersion;
}

DLLEXPORT int WolframLibrary_initialize(WolframLibraryData libData) {
  (void)libData;
  memset(g_writers, 0, sizeof(g_writers));
  g_last_error[0] = '\0';
  return LIBRARY_NO_ERROR;
}

DLLEXPORT void WolframLibrary_uninitialize(WolframLibraryData libData) {
  int i;
  (void)libData;
  for (i = 0; i < WILLOW_MAX_WRITERS; i++) {
    if (g_writers[i].pdf) {
      pdfioFileClose(g_writers[i].pdf);
      g_writers[i].pdf = NULL;
    }
  }
}

DLLEXPORT int willowLastError(WolframLibraryData libData, mint argc,
                              MArgument *args, MArgument result) {
  (void)libData;
  (void)argc;
  (void)args;
  MArgument_setUTF8String(result, g_last_error);
  return LIBRARY_NO_ERROR;
}

DLLEXPORT int willowWriterOpen(WolframLibraryData libData, mint argc,
                               MArgument *args, MArgument result) {
  char *filename;
  mint id = -1;
  int i;
  (void)argc;

  filename = MArgument_getUTF8String(args[0]);
  g_last_error[0] = '\0';

  for (i = 0; i < WILLOW_MAX_WRITERS; i++) {
    if (!g_writers[i].pdf) {
      g_writers[i].pdf = pdfioFileCreate(filename, NULL, NULL, NULL,
                                          pdf_error, NULL);
      if (g_writers[i].pdf) id = (mint)i + 1;
      break;
    }
  }

  if (i == WILLOW_MAX_WRITERS) set_error("Too many open Willow PDF writers.");
  libData->UTF8String_disown(filename);
  MArgument_setInteger(result, id);
  return LIBRARY_NO_ERROR;
}

DLLEXPORT int willowWriterClose(WolframLibraryData libData, mint argc,
                                MArgument *args, MArgument result) {
  mint id = MArgument_getInteger(args[0]);
  willow_writer_t *writer = writer_for_id(id);
  mint status = -1;
  (void)libData;
  (void)argc;

  if (!writer) {
    set_error("Invalid or already closed Willow PDF writer.");
  } else {
    status = pdfioFileClose(writer->pdf) ? 0 : -1;
    writer->pdf = NULL;
  }

  MArgument_setInteger(result, status);
  return LIBRARY_NO_ERROR;
}

DLLEXPORT int willowWriterAddImage(WolframLibraryData libData, mint argc,
                                   MArgument *args, MArgument result) {
  mint id = MArgument_getInteger(args[0]);
  MImage input = MArgument_getMImage(args[1]);
  double dpi = MArgument_getReal(args[2]);
  willow_writer_t *writer = writer_for_id(id);
  WolframImageLibrary_Functions image_api = libData->imageLibraryFunctions;
  MImage image = NULL;
  unsigned char *data;
  mint rows, columns, channels, colors;
  mbool alpha;
  colorspace_t color_space;
  pdfio_obj_t *image_obj;
  pdfio_dict_t *page_dict;
  pdfio_stream_t *page;
  pdfio_rect_t media_box;
  mint status = -1;
  (void)argc;

  if (!writer) {
    set_error("Invalid or already closed Willow PDF writer.");
    goto done;
  }
  if (!(dpi > 0.0)) {
    set_error("Image resolution must be positive.");
    goto done;
  }

  rows = image_api->MImage_getRowCount(input);
  columns = image_api->MImage_getColumnCount(input);
  channels = image_api->MImage_getChannels(input);
  alpha = image_api->MImage_alphaChannelQ(input);
  color_space = image_api->MImage_getColorSpace(input);
  colors = channels - (alpha ? 1 : 0);

  if (rows < 1 || columns < 1 ||
      !((color_space == MImage_CS_Gray && colors == 1) ||
        (color_space == MImage_CS_RGB && colors == 3))) {
    set_error("Images must use Gray or RGB color space.");
    goto done;
  }

  image = image_api->MImage_convertType(input, MImage_Type_Bit8, True);
  if (!image) {
    set_error("Could not convert the image to interleaved 8-bit pixels.");
    goto done;
  }
  data = image_api->MImage_getByteData(image);
  if (!data) {
    set_error("Could not access image pixels.");
    goto done;
  }

  image_obj = pdfioFileCreateImageObjFromData(writer->pdf, data,
                                               (size_t)columns, (size_t)rows,
                                               (size_t)colors, NULL,
                                               alpha ? true : false, true);
  if (!image_obj) goto done;

  media_box.x1 = 0.0;
  media_box.y1 = 0.0;
  media_box.x2 = 72.0 * (double)columns / dpi;
  media_box.y2 = 72.0 * (double)rows / dpi;

  page_dict = pdfioDictCreate(writer->pdf);
  if (!page_dict ||
      !pdfioDictSetRect(page_dict, "MediaBox", &media_box) ||
      !pdfioPageDictAddImage(page_dict, "IM1", image_obj)) {
    set_error("Could not create the PDF page dictionary.");
    goto done;
  }

  page = pdfioFileCreatePage(writer->pdf, page_dict);
  if (!page) goto done;
  if (!pdfioContentDrawImage(page, "IM1", 0.0, 0.0,
                             media_box.x2, media_box.y2) ||
      !pdfioStreamClose(page)) {
    set_error("Could not write the image page.");
    goto done;
  }

  status = 0;

done:
  if (image) image_api->MImage_free(image);
  MArgument_setInteger(result, status);
  return LIBRARY_NO_ERROR;
}

DLLEXPORT int willowWriterAddPages(WolframLibraryData libData, mint argc,
                                   MArgument *args, MArgument result) {
  mint id = MArgument_getInteger(args[0]);
  char *filename = MArgument_getUTF8String(args[1]);
  MTensor pages = MArgument_getMTensor(args[2]);
  willow_writer_t *writer = writer_for_id(id);
  pdfio_file_t *input = NULL;
  mint *page_data;
  mint page_count, requested_count, i;
  mint status = -1;
  (void)argc;

  if (!writer) {
    set_error("Invalid or already closed Willow PDF writer.");
    goto done;
  }

  input = pdfioFileOpen(filename, NULL, NULL, pdf_error, NULL);
  if (!input) goto done;

  page_count = (mint)pdfioFileGetNumPages(input);
  requested_count = libData->MTensor_getFlattenedLength(pages);
  page_data = libData->MTensor_getIntegerData(pages);

  for (i = 0; i < requested_count; i++) {
    mint page_number = page_data[i];
    if (page_number < 1 || page_number > page_count) {
      set_error("A requested page number is outside the input PDF.");
      goto done;
    }
    if (!pdfioPageCopy(writer->pdf,
                       pdfioFileGetPage(input, (size_t)(page_number - 1)))) {
      goto done;
    }
  }

  status = 0;

done:
  if (input) pdfioFileClose(input);
  libData->UTF8String_disown(filename);
  MArgument_setInteger(result, status);
  return LIBRARY_NO_ERROR;
}

DLLEXPORT int willowPageCount(WolframLibraryData libData, mint argc,
                              MArgument *args, MArgument result) {
  char *filename = MArgument_getUTF8String(args[0]);
  pdfio_file_t *input;
  mint count = -1;
  (void)argc;

  input = pdfioFileOpen(filename, NULL, NULL, pdf_error, NULL);
  if (input) {
    count = (mint)pdfioFileGetNumPages(input);
    pdfioFileClose(input);
  }

  libData->UTF8String_disown(filename);
  MArgument_setInteger(result, count);
  return LIBRARY_NO_ERROR;
}
