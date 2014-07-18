#include "iqa.h"
#include <stdio.h>
#include <string.h>
#include <fcntl.h>
#include <time.h>
#include <stdlib.h>
#include <unistd.h>
#include <pthread.h>

#define DO_MS_SSIM 0
#define THREAD_COUNT 8

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

struct frameinfo {
  int active;
  unsigned long frame_number;
  unsigned char* reference_frame_buffer;
  unsigned char* degraded_frame_buffer;
  float psnr_results[4];
  float ssim_results[4];
  float ms_ssim_results[4];
};

pthread_t threads[THREAD_COUNT];
struct frameinfo frames_info[THREAD_COUNT];

FILE* reference_file;
FILE* degraded_file;

unsigned int width = 0;
unsigned int height = 0;
unsigned int frame_size = 0;
unsigned long frame_count = 0;
int all_frames_read = 0;

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

void* analyze_frame_pair(void* thread_data) {
  struct frameinfo *frame = (struct frameinfo*)thread_data;
  double before,after;
  unsigned char* ref_plane_buf;
  unsigned char* deg_plane_buf;
  float luma_result, chroma_cb_result, chroma_cr_result;

  frame->active = 1;

  chroma_cb_result = 0.0;
  chroma_cr_result = 0.0;

  ref_plane_buf = frame->reference_frame_buffer;
  deg_plane_buf = frame->degraded_frame_buffer;
  before = get_current_time();
  luma_result =      iqa_psnr(ref_plane_buf, deg_plane_buf, width, height, width);
  // ref_plane_buf += (width*height);
  // deg_plane_buf += (width*height);
  // chroma_cb_result = iqa_psnr(ref_plane_buf, deg_plane_buf, width, height, width);
  // ref_plane_buf += (width*height);
  // deg_plane_buf += (width*height);
  // chroma_cr_result = iqa_psnr(ref_plane_buf, deg_plane_buf, width, height, width);
  after = get_current_time();

  frame->psnr_results[0] = luma_result;
  frame->psnr_results[1] = chroma_cb_result;
  frame->psnr_results[2] = chroma_cr_result;
  frame->psnr_results[3] = after-before;

  ref_plane_buf = frame->reference_frame_buffer;
  deg_plane_buf = frame->degraded_frame_buffer;
  before = get_current_time();
  luma_result =      iqa_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0, 0);
  // ref_plane_buf += (width*height);
  // deg_plane_buf += (width*height);
  // chroma_cb_result = iqa_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0, 0);
  // ref_plane_buf += (width*height);
  // deg_plane_buf += (width*height);
  // chroma_cr_result = iqa_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0, 0);
  after = get_current_time();

  frame->ssim_results[0] = luma_result;
  frame->ssim_results[1] = chroma_cb_result;
  frame->ssim_results[2] = chroma_cr_result;
  frame->ssim_results[3] = after-before;

  if (DO_MS_SSIM) {
    ref_plane_buf = frame->reference_frame_buffer;
    deg_plane_buf = frame->degraded_frame_buffer;
    before = get_current_time();
    luma_result =      iqa_ms_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0);
    // ref_plane_buf += (width*height);
    // deg_plane_buf += (width*height);
    // chroma_cb_result = iqa_ms_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0);
    // ref_plane_buf += (width*height);
    // deg_plane_buf += (width*height);
    // chroma_cr_result = iqa_ms_ssim(ref_plane_buf, deg_plane_buf, width, height, width, 0);
    after = get_current_time();
  }

  frame->ms_ssim_results[0] = luma_result;
  frame->ms_ssim_results[1] = chroma_cb_result;
  frame->ms_ssim_results[2] = chroma_cr_result;
  frame->ms_ssim_results[3] = after-before;

  pthread_exit(thread_data);
}

void validate_headers(FILE* stream, char* stream_name) {
  char buf[HEADER_BUFFER_SIZE];
  char* tag;
  unsigned int stream_width;
  unsigned int stream_height;

  // Running on the assumption that a STREAM or FRAME header line is never more than BUFFER_SIZE long.
  //   -- generally safe, especially with controlled streams, but not literally guaranteed.
  if (fgets(buf, HEADER_BUFFER_SIZE, stream) != NULL) {
    // printf("Header line: %s", buf);

    if (strstr(buf, "YUV4MPEG2") != buf) {
      error_exit("Unsupported file: %s is not YUV4MPEG formatted!", stream_name);
    }

    if (strstr(buf, "C444 ") == NULL) { // Note: 10-bit would be C444p10, for example.
      error_exit("Unsupported file: %s must be in 8-bit 4:4:4 format!", stream_name);
    }

    if ((tag = strstr(buf, " W")) != NULL) {
      sscanf(tag + 2, "%u", &stream_width);
      if (stream_width == 0) {
        error_exit("Couldn't determine %s frame width!", stream_name);
      }
    } else {
      error_exit("Couldn't determine %s frame width!", stream_name);
    }

    if ((tag = strstr(buf, " H")) != NULL) {
      sscanf(tag + 2, "%u", &stream_height);
      if (stream_height == 0) {
        error_exit("Couldn't determine %s frame height!", stream_name);
      }
    } else {
      error_exit("Couldn't determine %s frame height!", stream_name);
    }

  } else {
    error_exit("No %s input!", stream_name);
  }

  // Make sure we read the whole header before we go on.
  while (!feof(stream) && !strchr(buf, '\n')) {
    if (fgets(buf, HEADER_BUFFER_SIZE, stream) == NULL) {
      error_exit("Invalid %s input - no newline after header.", stream_name);
    }
  }
  if (feof(reference_file)) {
    error_exit("Invalid %s input - no newline after header.", stream_name);
  }

  if (stream_width < 32 || stream_height < 32) {
    error_exit("Invalid dimensions -- %s width and height must both be 16 or greater.", stream_name);
  }

  if (width == 0) {
    // First stream we're checking - just set the reference values.
    width = stream_width;
    height = stream_height;
  } else {
    // All other streams -- compare to reference values.
    if (stream_width != width || stream_height != height) {
      error_exit("Dimensions for %s do not match reference stream!", stream_name);
    }
  }
}

void read_frame_header(FILE* file, char* stream_name) {
  char buf[HEADER_BUFFER_SIZE];
  if (fgets(buf, HEADER_BUFFER_SIZE, file) != NULL) {
    if (strstr(buf, "FRAME") != buf) {
      error_exit("Frame header not found in %s!", stream_name);
    } else if (!strchr(buf, '\n')) {
      error_exit("Frame header in %s too long - aborting!", stream_name);
    }
  }
}

int read_next_frame(FILE* ref_file, struct frameinfo* frame) {
  unsigned int bytes_read;

  read_frame_header(ref_file, "reference stream");

  bytes_read = fread(frame->degraded_frame_buffer, 1, frame_size, ref_file);
  if (bytes_read < frame_size) {
    // All done.
    if (bytes_read > 0) printf("Warning: Final frame of reference stream was incomplete.\n");
    return 0;
  }

  return 1;
}

void* collect_results(void* t) {
  unsigned long frame_number = 0;
  int thread_number = 0;
  void* status;
  int result_code;
  struct frameinfo* frame;

  while (frame_number < frame_count || !all_frames_read) {
    if (frames_info[thread_number].active == 1) {
      result_code = pthread_join(threads[thread_number], &status);

      frame = &frames_info[thread_number];
      // printf("Frame %lu PSNR (%04dms):    luma = %7.5f, chroma_cb = %7.5f, chroma_cr = %7.5f\n", frame->frame_number, (int)(frame->psnr_results[3] * 1000), frame->psnr_results[0], frame->psnr_results[1], frame->psnr_results[2]);
      // printf("Frame %lu SSIM (%04dms):    luma = %7.5f, chroma_cb = %7.5f, chroma_cr = %7.5f\n", frame->frame_number, (int)(frame->ssim_results[3] * 1000), frame->ssim_results[0], frame->ssim_results[1], frame->ssim_results[2]);
      // printf("Frame %lu MS-SSIM (%04dms): luma = %7.5f, chroma_cb = %7.5f, chroma_cr = %7.5f\n", frame->frame_number, (int)(frame->ms_ssim_results[3] * 1000), frame->ms_ssim_results[0], frame->ms_ssim_results[1], frame->ms_ssim_results[2]);
      printf("Frame %lu PSNR:    luma = %8.5f, chroma_cb = %8.5f, chroma_cr = %8.5f\n", frame->frame_number, frame->psnr_results[0], frame->psnr_results[1], frame->psnr_results[2]);
      printf("Frame %lu SSIM:    luma = %8.5f, chroma_cb = %8.5f, chroma_cr = %8.5f\n", frame->frame_number, frame->ssim_results[0], frame->ssim_results[1], frame->ssim_results[2]);
      printf("Frame %lu MS-SSIM: luma = %8.5f, chroma_cb = %8.5f, chroma_cr = %8.5f\n", frame->frame_number, frame->ms_ssim_results[0], frame->ms_ssim_results[1], frame->ms_ssim_results[2]);      

      frame->active = 0;

      frame_number++;
      thread_number = frame_number % THREAD_COUNT;
    } else {
      usleep(100);
    }
  }

  pthread_exit(t);
}


// ffmpeg -i input.mp4 -pix_fmt yuv444p -f yuv4mpegpipe - | comparison_tool
int main(int argc,char* argv[]){
  int i, result_code;

  if ((argc != 2)) {
    fprintf(stderr, "Usage: %s <reference_file.y4m>\n", argv[0]);
    exit(1);
  }

  reference_file = fopen(argv[1], "r");
  if (reference_file < 0) {
    fprintf(stderr, "ERROR: Could not open reference file: %s\n", argv[1]);
    exit(2);
  }

  validate_headers(reference_file, "reference stream");

  frame_size = (unsigned int)(3 * width * height);
  DEBUG1("Frame size: %ux%u (%u bytes)", width, height, frame_size);

  for (i = 0; i < THREAD_COUNT; i++) {
    frames_info[i].active = 0;
    frames_info[i].reference_frame_buffer = malloc(frame_size);
    frames_info[i].degraded_frame_buffer = malloc(frame_size);
    if (frames_info[i].reference_frame_buffer == NULL || frames_info[i].degraded_frame_buffer == NULL) {
      error_exit("Out of memory allocating frame buffers!");
    }
  }

  pthread_attr_t attr;
  pthread_attr_init(&attr);
  pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_JOINABLE);

  pthread_t collect_results_thread;
  result_code = pthread_create(&collect_results_thread, &attr, collect_results, NULL);
  if (result_code) {
    error_exit("Error creating result collector thread: %d!", result_code);
  }

  int valid_stream = 1;
  int thread_number = 0;
  unsigned char* prev_frame_buffer = NULL;

  while (valid_stream && !feof(reference_file)) {   // && frame_count < 50) {
    if (frames_info[thread_number].active == 1) {
      usleep(100);
    } else {
      frames_info[thread_number].frame_number = frame_count;
      result_code = read_next_frame(reference_file, &frames_info[thread_number]);
      if (result_code == 0) {
        valid_stream = 0;
        break;
      }

      // For the first frame, we just compare to itself.
      if (prev_frame_buffer == NULL) prev_frame_buffer = frames_info[thread_number].degraded_frame_buffer;

      memcpy(frames_info[thread_number].reference_frame_buffer, prev_frame_buffer, frame_size);
      prev_frame_buffer = frames_info[thread_number].degraded_frame_buffer;

      result_code = pthread_create(&threads[thread_number], &attr, analyze_frame_pair, &frames_info[thread_number]);
      if (result_code) {
        error_exit("Error creating thread: %d!", result_code);
      }

      frame_count++;
      thread_number = frame_count % THREAD_COUNT;
    }
  }

  all_frames_read = 1;

  // printf("Finished reading frames!\n");

  pthread_exit(NULL);
  return 0;
}
