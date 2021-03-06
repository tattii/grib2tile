import numpy as np
cimport numpy as np
from io import BytesIO
import struct

DTYPE = np.uint8
ctypedef np.uint8_t DTYPE_t


def parse_radar(file):
    fileptr = open(file, 'rb')

    # section.4
    fileptr.seek(16 + 21 + 72 + 7)
    if struct.unpack('>H', fileptr.read(2))[0] != 50008 : return
    sec4 = parse_pdt_4_50008(fileptr)

    # section.5
    fileptr.seek(16 + 21 + 72 +  82 + 9)
    if struct.unpack('>H', fileptr.read(2))[0] != 200 : return
    sec5 = parse_drt_5_200(fileptr)

    # section.7
    fileptr.seek(16 + 21 + 72 +  82 + 519 + 6)
    return {
        'sec4': sec4,
        'sec5': sec5,
        'nx': 2560,
        'ny': 3360,
        'compr_data': parse_7_data(fileptr)
    }

def decode_compr_data(radar, level_values):
    data = decode_rle_levelvalues(
        radar['compr_data'],
        radar['nx'] * radar['ny'],
        radar['sec5']['nbit'],
        radar['sec5']['max_value'],
        level_values
    )
    return np.reshape(data, (radar['ny'], radar['nx']))


def parse_pdt_4_50008(fileptr):
    format = '>5B H 2B I 2B I 2B I H 6B H 3B H B H 8s 8s 8s'
    d = struct.unpack(
        format,
        fileptr.read(struct.calcsize(format)))
    return {
        'parameter_category': d[0],
        'parameter_number': d[1],
        'year': d[15],
        'month': d[16],
        'day': d[17],
        'hour': d[18],
        'minute': d[19],
        'second': d[20]
    }


def parse_drt_5_200(fileptr):
    format = '>B 2H B 251H'
    d = struct.unpack(
        format,
        fileptr.read(struct.calcsize(format)))
    drt = {
        'nbit': d[0],
        'max_value': d[1],
        'max_value_level': d[2],
        'decimal_scale_factor': d[3],
        'level_values': [-0.] # no data
    }
    scale_factor = pow(10., d[3])
    for v in d[4:]:
        drt['level_values'].append(v / scale_factor)
    return drt

def parse_7_data(fileptr):
    sec7_length = struct.unpack('>I', fileptr.read(4))[0]
    struct.unpack('>B', fileptr.read(1))
    data = fileptr.read(sec7_length - 5)
    return np.fromstring(data, dtype='>B')

def decode_rle_levelvalues(np.ndarray[DTYPE_t, ndim=1] compr_data, int ndata, int nbit, int maxv, np.ndarray[DTYPE_t, ndim=1] level_values):
    #out = np.empty(ndata, dtype='float16')
    cdef np.ndarray[DTYPE_t, ndim=1] out = np.empty(ndata, dtype=np.uint8)
    
    cdef int lngu = pow(2, nbit) - 1 - maxv
    cdef int pv = -1
    cdef int k = 0
    cdef int count = 1
    cdef int n = 0

    cdef int v

    for v in np.nditer(compr_data):
        if v <= maxv:
            if pv >= 0:
                out[k: k + count] = pv
                k += count
            count = 1
            n = 0
            pv = level_values[v]
        else:
            count += pow(lngu, n) * (v - maxv - 1)
            n += 1
    out[k: k + count] = pv
    return out

