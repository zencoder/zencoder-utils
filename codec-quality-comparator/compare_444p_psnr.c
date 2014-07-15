#include "iqa.h"
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <stdlib.h>
// #include <unistd.h>

int DEBUG = 0;
#define DEBUG1(fmt, ...) if (DEBUG >= 1) { printf("DEBUG1: "); printf(fmt, ##__VA_ARGS__); printf("\n"); }
#define DEBUG2(fmt, ...) if (DEBUG >= 2) { printf("DEBUG2: "); printf(fmt, ##__VA_ARGS__); printf("\n"); }
#define error_exit(fmt, ...) fprintf(stderr, "\nERROR: "); fprintf(stderr, fmt, ##__VA_ARGS__); fprintf(stderr, "\n"); exit(1);
#define HEADER_BUFFER_SIZE 256


#if defined CLOCK_MONOTONIC_COARSE
#define XCLOCK_MONOTONIC CLOCK_MONOTONIC_COARSE
#else
#define XCLOCK_MONOTONIC CLOCK_MONOTONIC
#endif

double timespec_to_double(struct timespec *the_time) {
  double decimal_time = (double)(the_time->tv_sec);
  decimal_time += (double)(the_time->tv_nsec) / 1e9;
  return decimal_time;
}

double get_current_time() {
  struct timespec now;
  clock_gettime(XCLOCK_MONOTONIC, &now);
  return timespec_to_double(&now);
}

void compare_psnr(unsigned long frame_number, unsigned char* ref_frame_buf, unsigned char* deg_frame_buf, unsigned int width, unsigned int height) {
  unsigned char* ref_plane_buf = ref_frame_buf;
  unsigned char* deg_plane_buf = deg_frame_buf;
  double before,after;

  float luma_result, chroma_cb_result, chroma_cr_result;

  before = get_current_time();
  luma_result =      iqa_psnr(ref_plane_buf, deg_plane_buf, width, height, width);
  ref_plane_buf += (width*height);
  deg_plane_buf += (width*height);
  chroma_cb_result = iqa_psnr(ref_plane_buf, deg_plane_buf, width, height, width);
  ref_plane_buf += (width*height);
  deg_plane_buf += (width*height);
  chroma_cr_result = iqa_psnr(ref_plane_buf, deg_plane_buf, width, height, width);
  after = get_current_time();

  printf("Frame %lu PSNR (%dms): luma = %0.5f, chroma_cb = %0.5f, chroma_cr = %0.5f\n", frame_number, (int)((after-before) * 1000), luma_result, chroma_cb_result, chroma_cr_result);

  ref_plane_buf = ref_frame_buf;
  deg_plane_buf = deg_frame_buf;

  before = get_current_time();
  luma_result =      iqa_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0, 0);
  ref_plane_buf += (width*height);
  deg_plane_buf += (width*height);
  chroma_cb_result = iqa_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0, 0);
  ref_plane_buf += (width*height);
  deg_plane_buf += (width*height);
  chroma_cr_result = iqa_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0, 0);
  after = get_current_time();

  printf("Frame %lu SSIM (%dms): luma = %0.5f, chroma_cb = %0.5f, chroma_cr = %0.5f\n", frame_number, (int)((after-before) * 1000), luma_result, chroma_cb_result, chroma_cr_result);

  ref_plane_buf = ref_frame_buf;
  deg_plane_buf = deg_frame_buf;

  before = get_current_time();
  luma_result =      iqa_ms_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0);
  ref_plane_buf += (width*height);
  deg_plane_buf += (width*height);
  chroma_cb_result = iqa_ms_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0);
  ref_plane_buf += (width*height);
  deg_plane_buf += (width*height);
  chroma_cr_result = iqa_ms_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0);
  after = get_current_time();

  printf("Frame %lu MS-SSIM (%dms): luma = %0.5f, chroma_cb = %0.5f, chroma_cr = %0.5f\n", frame_number, (int)((after-before) * 1000), luma_result, chroma_cb_result, chroma_cr_result);
}

// ffmpeg -i input.mp4 -pix_fmt yuv444p -f yuv4mpegpipe - | comparison_tool

int main(int argc,char* argv[]){
  if ((argc != 3)) {
    fprintf(stderr, "Usage: compare_444p_psnr <reference_file.y4m> <degraded_file.y4m>\n");
    exit(1);
  }

  FILE* reference_file = fopen(argv[1], "r");
  if (reference_file < 0) {
    fprintf(stderr, "ERROR: Could not open reference file: %s\n", argv[1]);
    exit(2);
  }

  FILE* degraded_file = fopen(argv[2], "r");
  if (degraded_file < 0) {
    fprintf(stderr, "ERROR: Could not open degraded file: %s\n", argv[2]);
    exit(2);
  }

  unsigned long frame_number = 0;
  unsigned int width = 0;
  unsigned int height = 0;
  unsigned int degraded_width = 0;
  unsigned int degraded_height = 0;
  char buf[HEADER_BUFFER_SIZE];
  char* tag;

  // Running on the assumption that a STREAM or FRAME header line is never more than BUFFER_SIZE long.
  //   -- generally safe, especially with controlled streams, but not literally guaranteed.
  if (fgets(buf, HEADER_BUFFER_SIZE, reference_file) != NULL) {
    // printf("Header line: %s", buf);

    if (strstr(buf, "YUV4MPEG2") != buf) {
      error_exit("Reference stream is not YUV4MPEG formatted!");
    }

    if (strstr(buf, "C444 ") == NULL) { // Note: 10-bit would be C444p10, for example.
      error_exit("Reference stream must be in 8-bit 4:4:4 format!");
    }

    if ((tag = strstr(buf, " W")) != NULL) {
      sscanf(tag + 2, "%u", &width);
      if (width == 0) {
        error_exit("Couldn't determine reference stream frame width!");
      }
    } else {
      error_exit("Couldn't determine reference stream frame width!");
    }

    if ((tag = strstr(buf, " H")) != NULL) {
      sscanf(tag + 2, "%u", &height);
      if (height == 0) {
        error_exit("Couldn't determine reference stream frame height!");
      }
    } else {
      error_exit("Couldn't determine reference stream frame height!");
    }

  } else {
    error_exit("No reference stream input!");
  }

  // Make sure we read the whole header before we go on.
  while (!feof(reference_file) && !strchr(buf, '\n')) {
    if (fgets(buf, HEADER_BUFFER_SIZE, reference_file) == NULL) {
      error_exit("Invalid reference stream input - no newline after header.");
    }
  }
  if (feof(reference_file)) {
    error_exit("Invalid reference stream input - no newline after header.");
  }

  if (width < 32 || height < 32) {
    error_exit("Invalid dimensions -- reference stream width and height must both be 16 or greater.");
  }



  // Running on the assumption that a STREAM or FRAME header line is never more than BUFFER_SIZE long.
  //   -- generally safe, especially with controlled streams, but not literally guaranteed.
  if (fgets(buf, HEADER_BUFFER_SIZE, degraded_file) != NULL) {
    // printf("Header line: %s", buf);

    if (strstr(buf, "YUV4MPEG2") != buf) {
      error_exit("Degraded stream is not YUV4MPEG formatted!");
    }

    if (strstr(buf, "C444 ") == NULL) { // Note: 10-bit would be C444p10, for example.
      error_exit("Degraded stream must be in 8-bit 4:4:4 format!");
    }

    if ((tag = strstr(buf, " W")) != NULL) {
      sscanf(tag + 2, "%u", &degraded_width);
      if (degraded_width == 0) {
        error_exit("Couldn't determine degraded stream frame width!");
      } else if (degraded_width != width) {
        error_exit("Degraded stream frame width not same as reference stream!");
      }        
    } else {
      error_exit("Couldn't determine degraded stream frame width!");
    }

    if ((tag = strstr(buf, " H")) != NULL) {
      sscanf(tag + 2, "%u", &degraded_height);
      if (degraded_height == 0) {
        error_exit("Couldn't determine degraded stream frame height!");
      } else if (degraded_height != height) {
        error_exit("Degraded stream frame height not same as reference stream!");          
      }
    } else {
      error_exit("Couldn't determine degraded stream frame height!");
    }

  } else {
    error_exit("No degraded stream input!");
  }

  // Make sure we read the whole header before we go on.
  while (!feof(degraded_file) && !strchr(buf, '\n')) {
    if (fgets(buf, HEADER_BUFFER_SIZE, degraded_file) == NULL) {
      error_exit("Invalid degraded stream input - no newline after header.");
    }
  }
  if (feof(degraded_file)) {
    error_exit("Invalid degraded stream input - no newline after header.");
  }


  int valid_stream = 1;
  unsigned int bytes_read;
  unsigned int frame_size = 0;
  unsigned char* reference_frame_buffer = NULL;
  unsigned char* degraded_frame_buffer = NULL;

  frame_size = (unsigned int)(3 * width * height);
  DEBUG1("Frame size: %ux%u (%u bytes)", width, height, frame_size);
  
  reference_frame_buffer = malloc(frame_size);
  if (reference_frame_buffer == NULL) {
    error_exit("Out of memory getting reference frame buffer!");
  }
  
  degraded_frame_buffer = malloc(frame_size);
  if (degraded_frame_buffer == NULL) {
    error_exit("Out of memory getting degraded frame buffer!");
  }

  while (valid_stream && !feof(reference_file) && frame_number < 50) {
    // Read the frame header.
    if (fgets(buf, HEADER_BUFFER_SIZE, reference_file) != NULL) {
      // printf("Frame header line: %s", buf);

      if (strstr(buf, "FRAME") != buf) {
        error_exit("Frame header not found in reference stream!");
      } else if (!strchr(buf, '\n')) {
        error_exit("Frame header in reference stream too long - aborting!");
      } else {
        DEBUG1("Got reference frame header %lu...", frame_number);
      }
    }

    bytes_read = fread(reference_frame_buffer, 1, frame_size, reference_file);

    if (bytes_read == 0) {
      // All done.
      valid_stream = 0;
    } else if (bytes_read < frame_size) {
      printf("Warning: Final frame of reference stream was incomplete.\n");
      valid_stream = 0;
    }

    // Read the frame header.
    if (fgets(buf, HEADER_BUFFER_SIZE, degraded_file) != NULL) {
      // printf("Frame header line: %s", buf);

      if (strstr(buf, "FRAME") != buf) {
        error_exit("Frame header not found in degraded stream!");
      } else if (!strchr(buf, '\n')) {
        error_exit("Frame header in degraded stream too long - aborting!");
      } else {
        DEBUG1("Got degraded frame header %lu...", frame_number);
      }
    }

    bytes_read = fread(degraded_frame_buffer, 1, frame_size, degraded_file);

    if (bytes_read == 0) {
      // All done.
      valid_stream = 0;
    } else if (bytes_read < frame_size) {
      printf("Warning: Final frame of degraded stream was incomplete.\n");
      valid_stream = 0;
    }

    if (valid_stream) {
      compare_psnr(frame_number, reference_frame_buffer, degraded_frame_buffer, width, height);
    }

    frame_number++;
  }


  return 0;
}
