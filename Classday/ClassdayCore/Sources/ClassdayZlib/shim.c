#include "classday_zlib.h"

#include <string.h>
#include <zlib.h>

int classday_inflate_raw(const unsigned char *src, int src_len, unsigned char *dst, int dst_len) {
    z_stream stream;
    memset(&stream, 0, sizeof(stream));
    if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
        return -1;
    }
    stream.next_in = (Bytef *)src;
    stream.avail_in = (uInt)src_len;
    stream.next_out = dst;
    stream.avail_out = (uInt)dst_len;
    int status = inflate(&stream, Z_FINISH);
    int written = (int)stream.total_out;
    inflateEnd(&stream);
    if (status != Z_STREAM_END || written != dst_len) {
        return -1;
    }
    return written;
}
