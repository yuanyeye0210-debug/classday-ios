#ifndef CLASSDAY_ZLIB_H
#define CLASSDAY_ZLIB_H

/* Raw DEFLATE (ZIP method 8). Returns the number of bytes written, or -1. */
int classday_inflate_raw(const unsigned char *src, int src_len, unsigned char *dst, int dst_len);

#endif
