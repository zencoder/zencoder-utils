
CC = gcc
INCLUDES = -Iiqa/include

# Release flags
CFLAGS=-O3 -Wall

# Debug Flags
# CFLAGS=-g -Wall

# LIBS=iqa/build/debug/libiqa.a -lm -lrt -lprofiler
LIBS=iqa/build/debug/libiqa.a -lm -lrt
LFLAGS=-L.


# http://i0.kym-cdn.com/photos/images/newsfeed/000/234/739/fa5.jpg

all: compare_444p_psnr frame_to_frame_diff

.c.o:
	$(CC) $(INCLUDES) $(CFLAGS) -c $< -o $@

compare_444p_psnr: compare_444p_psnr.o
	$(CC) $(INCLUDES) $(CFLAGS) $(LFLAGS) $^ $(LIBS) -o $@

frame_to_frame_diff: frame_to_frame_diff.o
	$(CC) $(INCLUDES) $(CFLAGS) $(LFLAGS) $^ $(LIBS) -o $@

clean:
	rm *.o compare_444p_psnr frame_to_frame_diff
