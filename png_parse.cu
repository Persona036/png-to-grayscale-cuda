#include <png.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const uint8_t PNG_SIGNATURE[8] = {137, 80, 78, 71, 13, 10, 26, 10};

png_bytep *read_png_rgb(FILE *fp, int *width, int *height) {
  png_structp png =
      png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
  png_infop info = png_create_info_struct(png);

  png_init_io(png, fp);
  png_read_info(png, info);

  *width = png_get_image_width(png, info);
  *height = png_get_image_height(png, info);
  png_byte color_type = png_get_color_type(png, info);
  png_byte bit_depth = png_get_bit_depth(png, info);

  if (bit_depth == 16)
    png_set_strip_16(png);
  if (color_type == PNG_COLOR_TYPE_PALETTE)
    png_set_palette_to_rgb(png);
  if (color_type == PNG_COLOR_TYPE_GRAY && bit_depth < 8)
    png_set_expand_gray_1_2_4_to_8(png);
  if (color_type == PNG_COLOR_TYPE_GRAY ||
      color_type == PNG_COLOR_TYPE_GRAY_ALPHA)
    png_set_gray_to_rgb(png);
  png_set_strip_alpha(png);

  png_read_update_info(png, info);

  png_bytep *color_data = (png_bytep *)malloc(sizeof(png_bytep) * (*height));
  for (int y = 0; y < *height; y++)
    color_data[y] = (png_bytep)malloc(png_get_rowbytes(png, info));

  png_read_image(png, color_data);
  png_destroy_read_struct(&png, &info, NULL);

  return color_data;
}

int main(int argc, char *argv[]) {
  if (argc <= 1) {
    printf("Please provide a PNG\n");
    return 1;
  }
  const char *input_filepath = argv[1];
  uint8_t file_signature[8];

  FILE *input_file = fopen(input_filepath, "rb");
  if (input_file == NULL) {
    return 1;
  }

  fread(file_signature, sizeof(file_signature), 1, input_file);

  for (int i = 0; i < sizeof(file_signature); i++) {
    printf("%u ", file_signature[i]);
  }
  printf("\n");

  if (memcmp(file_signature, PNG_SIGNATURE, sizeof(PNG_SIGNATURE)) != 0) {
    fprintf(stderr, "ERROR: %s does not appear to be a valid PNG\n",
            input_filepath);
    return 1;
  }
  printf("PNG has a valid signature\n");

  rewind(input_file);

  int width, height;
  png_bytep *color_data = read_png_rgb(input_file, &width, &height);

  printf("Image: %dx%d\n", width, height);
  printf("First pixel RGB: (%d, %d, %d, %d)\n", color_data[0][0],
         color_data[0][1], color_data[0][2], color_data[0][3]);

  // PNG data is now RGB, accessible via color_data[y][x * 3 + color_value]
  // with color_value being 0, 1 or 2 depending on which color you want to
  // access

  // As required by CUDA, 2D arrays have to be flattened to 1D
  uint8_t *flat_data =
      (uint8_t *)malloc(height * width * 3 * sizeof(uint8_t));

  // copy entire row of data per y value
  for (int y = 0; y < height; y++) {
    memcpy(&flat_data[y * width * 3], color_data[y], width * 3);
  }

  // to access RGB data of y, x points in the flat 1D array use following
  // formula [(y * width + x) * 3 + color_value]

  printf("Flat 1D middle pixel point RGB: (%d, %d, %d)",
         flat_data[(128 * width + 128) * 3 + 0],
         flat_data[(128 * width + 128) * 3 + 1],
         flat_data[(128 * width + 128) * 3 + 2]);

  for (int y = 0; y < height; y++)
    free(color_data[y]);
  free(color_data);
  free(flat_data);
  fclose(input_file);
  return 0;
}
