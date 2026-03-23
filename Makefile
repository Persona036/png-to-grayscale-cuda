NVCC ?= nvcc
NVCCFLAGS = -std=c++11 -Xcompiler -Wall
PNG_CFLAGS = $(shell pkg-config --cflags libpng)
PNG_LIBS = $(shell pkg-config --libs libpng)

png_parser: src/png_parse.cu
	$(NVCC) $(NVCCFLAGS) $(PNG_CFLAGS) -o png_parser src/png_parse.cu $(PNG_LIBS)

run: png_parser
	./png_parser fish.png

clean:
	rm -f png_parser
