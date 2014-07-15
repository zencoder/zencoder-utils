
SRC= \
	compare_444p_psnr.c

OBJ = $(SRC:.c=.o)

INCLUDES = -Iiqa/include

CC = gcc

# Release flags
CFLAGS=-O2 -Wall

# Debug Flags
# CFLAGS=-g -Wall

LIBS=iqa/build/debug/libiqa.a -lm -lrt -lprofiler
LFLAGS=-L.

OUT = compare_444p_psnr


# http://i0.kym-cdn.com/photos/images/newsfeed/000/234/739/fa5.jpg

.c.o:
	$(CC) $(INCLUDES) $(CFLAGS) -c $< -o $@

$(OUT): $(OBJ)
	$(CC) $(INCLUDES) $(CFLAGS) $(LFLAGS) $^ $(LIBS) -o $@

