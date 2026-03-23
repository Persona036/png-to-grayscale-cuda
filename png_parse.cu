#include <png.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

const uint8_t PNG_SIGNATURE[8] = {137, 80, 78, 71, 13, 10, 26, 10};

__global__ void colortoGrayscaleConversion(unsigned char *Pout, unsigned char *Pin, int width, int height) {
    int col = blockIdx.x * blockDim.x + threadIdx.x;
    int row = blockIdx.y * blockDim.y + threadIdx.y;

    if (col < width && row < height) {
        int grayOffset = row*width + col;

        int rgbOffset = grayOffset * 3;

        unsigned char r = Pin[rgbOffset];
        unsigned char g = Pin[rgbOffset + 1];
        unsigned char b = Pin[rgbOffset + 2];


        Pout[grayOffset] = 0.21f*r + 0.71f*g +0.07f*b;
    }
}

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

void write_png_gray(const char *filename, uint8_t *gray_data, int width, int height) {
  FILE *fp = fopen(filename, "wb");
  if (!fp) {
    fprintf(stderr, "ERROR: Could not open %s for writing\n", filename);
    return;
  }

  png_structp png =
      png_create_write_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
  png_infop info = png_create_info_struct(png);

  png_init_io(png, fp);
  png_set_IHDR(png, info, width, height, 8, PNG_COLOR_TYPE_GRAY,
               PNG_INTERLACE_NONE, PNG_COMPRESSION_TYPE_DEFAULT,
               PNG_FILTER_TYPE_DEFAULT);
  png_write_info(png, info);

  for (int y = 0; y < height; y++)
    png_write_row(png, &gray_data[y * width]);

  png_write_end(png, NULL);
  png_destroy_write_struct(&png, &info);
  fclose(fp);
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
  printf("First pixel RGB: (%d, %d, %d)\n", color_data[0][0],
         color_data[0][1], color_data[0][2]);

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

  int mid_x = width / 2;
  int mid_y = height / 2;
  printf("Flat 1D middle pixel RGB: (%d, %d, %d)\n",
         flat_data[(mid_y * width + mid_x) * 3 + 0],
         flat_data[(mid_y * width + mid_x) * 3 + 1],
         flat_data[(mid_y * width + mid_x) * 3 + 2]);

  size_t rgb_size = (size_t)width * height * 3 * sizeof(uint8_t);
  size_t gray_size = (size_t)width * height * sizeof(uint8_t);

  unsigned char *d_rgb, *d_gray;
  cudaMalloc((void **)&d_rgb, rgb_size);
  cudaMalloc((void **)&d_gray, gray_size);

  cudaMemcpy(d_rgb, flat_data, rgb_size, cudaMemcpyHostToDevice);

  dim3 blockDim(16, 16);
  dim3 gridDim((width + blockDim.x - 1) / blockDim.x,
               (height + blockDim.y - 1) / blockDim.y);

  colortoGrayscaleConversion<<<gridDim, blockDim>>>(d_gray, d_rgb, width, height);
  cudaDeviceSynchronize();

  uint8_t *gray_data = (uint8_t *)malloc(gray_size);
  cudaMemcpy(gray_data, d_gray, gray_size, cudaMemcpyDeviceToHost);

  printf("Grayscale middle pixel: %d\n", gray_data[mid_y * width + mid_x]);
  printf("Grayscale first pixel: %d\n", gray_data[0]);
  printf("Grayscale last pixel: %d\n", gray_data[width * height - 1]);

  write_png_gray("output.png", gray_data, width, height);
  printf("Wrote grayscale image to output.png\n");

  cudaFree(d_rgb);
  cudaFree(d_gray);

  for (int y = 0; y < height; y++)
    free(color_data[y]);
  free(color_data);
  free(flat_data);
  free(gray_data);
  fclose(input_file);
  return 0;
}
