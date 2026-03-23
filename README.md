# png-to-grayscale-cuda

Small CUDA example that reads a PNG using `libpng` and converts it to grayscale using the GPU.

## Dependencies
Make sure you have the following installed:
- CUDA Toolkit (`nvcc`)
- `libpng`
- `pkg-config`
- `make`

## Build

```sh
make

```

## Run

```sh
./png_parser input.png

```

or to run the sample that i have included:

```sh
make run

```
