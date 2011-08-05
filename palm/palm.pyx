ctypedef int int32_t
ctypedef long long int64_t
ctypedef unsigned int uint32_t
ctypedef unsigned long long uint64_t

cdef extern from "stdlib.h":
    void free(void *)

cdef extern from "palmcore.h":
    ctypedef struct pbf_protobuf:
        pass
    pbf_protobuf * pbf_load(char *data, uint64_t size)
    void pbf_free(pbf_protobuf *pbf)
    int pbf_get_bytes(pbf_protobuf *pbf, uint64_t field_num,
        char **out, uint64_t *length)
    int pbf_get_integer(pbf_protobuf *pbf, uint64_t field_num, uint64_t *res)
    int pbf_get_signed_integer(pbf_protobuf *pbf,
        uint64_t field_num, int64_t *res,
        int32_t *res32, int use_zigzag)
    int pbf_exists(pbf_protobuf *pbf, uint64_t field_num)
    int pbf_set_bytes(pbf_protobuf *pbf, uint64_t field_num,
        char *out, uint64_t length)
    unsigned char *pbf_serialize(pbf_protobuf *pbf, int *length)

    int pbf_set_integer(pbf_protobuf *pbf, uint64_t field_num,
        uint64_t value, int fixed)
    int pbf_set_signed_integer(pbf_protobuf *pbf, uint64_t field_num,
        int64_t value, int zigzag)

    void pbf_remove(pbf_protobuf *pbf, uint64_t field_num)

class ProtoFieldMissing(Exception): pass
class ProtoDataError(Exception): pass

cdef class ProtoBase:
    (TYPE_string,
     TYPE_bytes,
     TYPE_int32,
     TYPE_int64,
     TYPE_uint32,
     TYPE_uint64,
     TYPE_sint32,
     TYPE_sint64,
     ) = range(8)
    cdef pbf_protobuf *buf

    cdef int CTYPE_string
    cdef int CTYPE_bytes
    cdef int CTYPE_int32
    cdef int CTYPE_int64
    cdef int CTYPE_uint32
    cdef int CTYPE_uint64
    cdef int CTYPE_sint32
    cdef int CTYPE_sint64

    def __init__(self, data):
        self.data = data
        self.buf = pbf_load(data, len(data))
        if (self.buf == NULL):
            self.data = None
            raise ProtoDataError("Invalid or unsupported protobuf data")
        self.CTYPE_string = self.TYPE_string
        self.CTYPE_bytes = self.TYPE_bytes
        self.CTYPE_int32 = self.TYPE_int32
        self.CTYPE_int64 = self.TYPE_int64
        self.CTYPE_uint32 = self.TYPE_uint32
        self.CTYPE_uint64 = self.TYPE_uint64
        self.CTYPE_sint32 = self.TYPE_sint32
        self.CTYPE_sint64 = self.TYPE_sint64

    def _buf_get(self, field, typ, name):
        cdef int ctyp = typ
        cdef char *res
        cdef uint64_t rlen
        cdef int32_t si
        cdef int64_t sq
        cdef uint64_t uq

        cdef int got
        if ctyp == self.CTYPE_string:
            got = pbf_get_bytes(self.buf, field, &res, &rlen)
            if not got:
                raise ProtoFieldMissing(name)
            return unicode(res[:rlen], "utf-8")
        elif ctyp == self.CTYPE_bytes:
            got = pbf_get_bytes(self.buf, field, &res, &rlen)
            if not got:
                raise ProtoFieldMissing(name)
            return res[:rlen]
        elif ctyp == self.CTYPE_int32:
            got = pbf_get_signed_integer(self.buf,
                    field, NULL, &si, 0)
            if not got:
                raise ProtoFieldMissing(name)
            return si
        elif ctyp == self.CTYPE_sint32:
            got = pbf_get_signed_integer(self.buf,
                    field, NULL, &si, 1)
            if not got:
                raise ProtoFieldMissing(name)
            return si
        elif ctyp == self.CTYPE_uint32 or ctyp == self.CTYPE_uint64:
            got = pbf_get_integer(self.buf,
                    field, &uq)
            if not got:
                raise ProtoFieldMissing(name)
            return uq
        elif ctyp == self.CTYPE_int64:
            got = pbf_get_signed_integer(self.buf,
                    field, &sq, NULL, 0)
            if not got:
                raise ProtoFieldMissing(name)
            return sq
        elif ctyp == self.CTYPE_sint64:
            got = pbf_get_signed_integer(self.buf,
                    field, &sq, NULL, 1)
            if not got:
                raise ProtoFieldMissing(name)
            return sq

        assert 0, "should not reach here!"

    def _buf_exists(self, field):
        cdef int e
        e = pbf_exists(self.buf, field)
        return bool(e)

    def _buf_del(self, field):
        pbf_remove(self.buf, field)

    def __dealloc__(self):
        if self.buf != NULL:
            pbf_free(self.buf)

    def _save(self, mods, cache):
        cdef int ctyp
        for f, v in cache.iteritems():
            if f in mods:
                ctyp = mods[f]
                if ctyp == self.CTYPE_string:
                    if type(v) is unicode:
                        v = v.encode("utf-8")
                    l = len(v)
                    pbf_set_bytes(self.buf,
                        f, v, l)
                elif ctyp == self.CTYPE_bytes:
                    l = len(v)
                    pbf_set_bytes(self.buf,
                        f, v, l)
                elif ctyp == self.CTYPE_uint32 or ctyp == self.CTYPE_uint64:
                    pbf_set_signed_integer(self.buf, f, v, 0)
                elif ctyp == self.CTYPE_int32 or ctyp == self.CTYPE_int64:
                    pbf_set_signed_integer(self.buf, f, v, 0)
                elif ctyp == self.CTYPE_sint32 or ctyp == self.CTYPE_sint64:
                    pbf_set_signed_integer(self.buf, f, v, 1)
                else:
                    assert 0, "unimplemented"

    def _serialize(self):
        cdef unsigned char *cout
        cdef int length
        cout = pbf_serialize(self.buf, &length)
        pyout = cout[:length]
        free(cout)
        return pyout
