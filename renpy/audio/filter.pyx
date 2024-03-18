# Copyright 2004-2024 Tom Rothamel <pytom@bishoujo.us>
#
# Permission is hereby granted, free of charge, to any person
# obtaining a copy of this software and associated documentation files
# (the "Software"), to deal in the Software without restriction,
# including without limitation the rights to use, copy, modify, merge,
# publish, distribute, sublicense, and/or sell copies of the Software,
# and to permit persons to whom the Software is furnished to do so,
# subject to the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


from libc.stdlib cimport calloc, free
from libc.string cimport memcpy

from cpython.object cimport PyObject

from libc.math cimport M_PI

import math

DEF SUBCHANNELS = 16

# A list of samples that are being passed around through the filter system.
# Sample i of channel j is at data[i * subchannels + j].
#
# An AudioFilter should always return a new SampleBuffer, or one that is
# returned to it. It should deallocate any SampleBuffer that are returned
# to it, that it does not return. It should not deallocate its input.
cdef struct SampleBuffer:

    # The number of subchannels.
    int subchannels

    # The number of samples allocated in the buffer.
    int allocated_length

    # The number of samples in the buffer actually used.
    int length

    # The samples themselves.
    float *samples

    # A linked list of sample buffers with the same number of subchannels.
    SampleBuffer *next

# A linked list of sample buffers with 0-16 subchannels.
cdef SampleBuffer *free_buffers[SUBCHANNELS]

cdef SampleBuffer *allocate_buffer(int subchannels, int length) nogil:
    """
    Allocates a sample buffer.
    """

    cdef SampleBuffer *buf
    cdef int size

    if free_buffers[subchannels] is not NULL:
        buf = free_buffers[subchannels]
        free_buffers[subchannels] = buf.next
    else:
        buf = <SampleBuffer *> calloc(1, sizeof(SampleBuffer))
        buf.subchannels = subchannels
        buf.allocated_length = 0
        buf.samples = NULL

    if buf.allocated_length < length:
        size = length * subchannels * sizeof(float)

        if buf.samples is not NULL:
            free(buf.samples)

        buf.samples= <float *> calloc(1, size)
        buf.allocated_length = length

    buf.length = length

    return buf


cdef void free_buffer(SampleBuffer *buf) nogil:
    """
    Frees a sample buffer, by putting it back on the free list.
    """

    buf.next = free_buffers[buf.subchannels]
    free_buffers[buf.subchannels] = buf


cdef class AudioFilter:

    def check_subchannels(self, int subchannels):
        """
        Checks if the filter can handle the given number of subchannels. This
        should raise an exception if the number of subchannels is not supported,
        and return the number of subchannels that the filter will return if is.
        """

        raise NotImplementedError("check_subchannels")

    def prepare(self, samplerate):
        """
        Prepares the filter for use at the given samplerate. This should be
        called before apply. It should be called for all children of the filter.

        Prepare may be called on the same filter multiple times, with the same
        samplerate. It should be safe to call prepare multiple times.
        """

        raise NotImplementedError("prepare")

    cdef SampleBuffer *apply(self, SampleBuffer *samples) nogil:
        """
        Applies the filter to the given samples.
        """

        return allocate_buffer(samples.subchannels, samples.length)


cdef class Sequence(AudioFilter):
    """
    A filter that applies a series of filters in sequence.
    """

    # The filters, in a Python list.
    cdef list filters

    # The filters, in a C array.
    cdef PyObject *cfilters[8]

    # The number of filter objects in the array.
    cdef int filter_count

    def __init__(self, filters):
        filters = [ to_audio_filter(f) for f in filters ]

        if len(filters) > 8:
            split = len(filters) // 2
            filters = [ Sequence(filters[:split]), Sequence(filters[split:]) ]

        self.filters = filters

        self.filter_count = len(filters)

        for i, f in enumerate(filters):
            self.filters[i] = f

    def check_subchannels(self, int subchannels):

        for f in self.filters:
            subchannels = f.check_subchannels(subchannels)

        return subchannels

    def prepare(self, int samplerate):

        for f in self.filters:
            f.prepare(samplerate)

    cdef SampleBuffer *apply(self, SampleBuffer *samples) nogil:

        cdef SampleBuffer *result = allocate_buffer(samples.subchannels, samples.length)
        cdef SampleBuffer *old_result = samples

        for i in range(self.filter_count):
            result = (<AudioFilter> self.cfilters[i]).apply(old_result)

            if result != samples:
                free_buffer(old_result)

            old_result = result

        return result


cdef class Biquad(AudioFilter):
    """
    :doc: audio_filter

    The biquad filter implements a variety of common audio filters. This takes
    three parameter, with `kind` controlling the type of filter, and the meaning
    of `frequency`, `q`, and `gain` depending on the kind.

    The following kinds of filters exist:

    "lowpass", "highpass"
        A lowpass or highpass filter, respectively. The `frequency` parameter
        controls the cutoff frequency, and the `q` parameter controls the
        sharpness of the cutoff. The `gain` parameter is ignored.

    "bandpass"
        A bandpass filter. The `frequency` parameter controls the center
        frequency, and the `q` parameter controls the sharpness of the cutoff.
        The `gain` parameter is ignored.

    "lowshelf", "highshelf"
        A lowshelf or highshelf filter, respectively. The `frequency` parameter
        controls the center frequency. Frequencies higher or lower than `frequency`
        get boosted by `gain` decibels, while other frequences are ignored. The
        `q` parameter is not used.

    "peaking"
        Frequences inside a range surrounding `frequency` are boosted by `gain`
        decibels. `q` controls the sharpness of the peak.

    "notch"
        The opposite of a bandpass filter. Frequences inside a range surrounding
        `frequency` are ignored, while other frequences are passed through. `q`
        controls the sharpness of the cutoff. The `gain` parameter is ignored.

    "allpass"
        A second-order allpass filter. Lets all frequencies through, but shifts
        the phase of some frequencies. The `frequency` parameter controls the frequency
        with the maximum group delay. `q` controls the sharpness of the phase shift.
        `gain` is ignored.

    This is meant to have similar effects to the biquad filter defined in the
    Web Audio API, documented at `https://developer.mozilla.org/en-US/docs/Web/API/BiquadFilterNode`_.
    It's implemented using the formulas from  `https://webaudio.github.io/Audio-EQ-Cookbook/Audio-EQ-Cookbook.txt`_.
    """

    # Based on:

    # https://webaudio.github.io/Audio-EQ-Cookbook/Audio-EQ-Cookbook.txt

    # In this, x_0 is the input, x_1 is the input from the previous sample, and
    # x_2 is the input from two samples ago. y_0, y_1, and y_2 are the same for
    # the output.

    cdef public object kind
    cdef public float frequency
    cdef public float q
    cdef public float gain

    # The last two samples of input data.
    cdef float last_x_1[SUBCHANNELS]
    cdef float last_x_2[SUBCHANNELS]

    # The last two samples of output data.
    cdef float last_y_1[SUBCHANNELS]
    cdef float last_y_2[SUBCHANNELS]

    # The coefficients.
    cdef float cx0, cx1, cx2, cy1, cy2

    cdef bint prepared

    def __init__(self, kind, frequency=350, q=1.0, gain=0):

        if kind not in { "lowpass", "highpass", "bandpass", "lowshelf", "highshelf", "peaking", "notch", "allpass" }:
            raise ValueError("Invalid kind {!r}.".format(kind))

        self.kind = kind
        self.frequency = frequency
        self.q = q
        self.gain = gain

    def check_subchannels(self, int subchannels):
        return subchannels

    def prepare(self, samplerate):

        if self.prepared:
            return

        self.prepared = True

        # The provided variables.
        Fs = samplerate
        f0 = self.frequency
        dBgain = self.gain
        Q = self.q

        # Intermediates.
        A = 10 ** (dBgain / 40)

        w0 = 2 * M_PI * self.frequency / Fs

        cos_w0 = math.cos(w0)
        sin_w0 = math.sin(w0)

        alpha = sin_w0 / (2 * Q)

        two_sqrt_A_alpha = 2 * math.sqrt(A) * alpha

        # The coefficients.
        if self.kind == "lowpass":
            b0 =  (1 - cos_w0)/2
            b1 =   1 - cos_w0
            b2 =  (1 - cos_w0)/2
            a0 =   1 + alpha
            a1 =  -2*cos_w0
            a2 =   1 - alpha

        elif self.kind == "highpass":

            b0 =  (1 + cos_w0)/2
            b1 = -(1 + cos_w0)
            b2 =  (1 + cos_w0)/2
            a0 =   1 + alpha
            a1 =  -2*cos_w0
            a2 =   1 - alpha

        elif self.kind == "bandpass":

            # (constant skirt gain, peak gain = Q)

            b0 =   sin_w0/2
            b1 =   0
            b2 =  -sin_w0/2
            a0 =   1 + alpha
            a1 =  -2*cos_w0
            a2 =   1 - alpha


            # (constant 0 dB peak gain)

            # b0 =   alpha
            # b1 =   0
            # b2 =  -alpha
            # a0 =   1 + alpha
            # a1 =  -2*cos_w0
            # a2 =   1 - alpha


        elif self.kind == "notch":

            b0 =   1
            b1 =  -2*cos_w0
            b2 =   1
            a0 =   1 + alpha
            a1 =  -2*cos_w0
            a2 =   1 - alpha


        elif self.kind == "allpass":

            b0 =   1 - alpha
            b1 =  -2*cos_w0
            b2 =   1 + alpha
            a0 =   1 + alpha
            a1 =  -2*cos_w0
            a2 =   1 - alpha


        elif self.kind == "peaking":

            b0 =   1 + alpha*A
            b1 =  -2*cos_w0
            b2 =   1 - alpha*A
            a0 =   1 + alpha/A
            a1 =  -2*cos_w0
            a2 =   1 - alpha/A

        elif self.kind == "lowshelf":

            b0 =    A*( (A+1) - (A-1)*cos_w0 + two_sqrt_A_alpha )
            b1 =  2*A*( (A-1) - (A+1)*cos_w0                   )
            b2 =    A*( (A+1) - (A-1)*cos_w0 - two_sqrt_A_alpha )
            a0 =        (A+1) + (A-1)*cos_w0 + two_sqrt_A_alpha
            a1 =   -2*( (A-1) + (A+1)*cos_w0                   )
            a2 =        (A+1) + (A-1)*cos_w0 - two_sqrt_A_alpha


        elif self.kind == "highshelf":

            b0 =    A*( (A+1) + (A-1)*cos_w0 + two_sqrt_A_alpha )
            b1 = -2*A*( (A-1) + (A+1)*cos_w0                   )
            b2 =    A*( (A+1) + (A-1)*cos_w0 - two_sqrt_A_alpha )
            a0 =        (A+1) - (A-1)*cos_w0 + two_sqrt_A_alpha
            a1 =    2*( (A-1) - (A+1)*cos_w0                   )
            a2 =        (A+1) - (A-1)*cos_w0 - two_sqrt_A_alpha

        self.cx0 = b0 / a0
        self.cx1 = b1 / a0
        self.cx2 = b2 / a0

        self.cy1 = a1 / a0
        self.cy2 = a2 / a0


    cdef SampleBuffer *apply(self, SampleBuffer *samples) nogil:

        cdef SampleBuffer *result = allocate_buffer(samples.subchannels, samples.length)
        cdef int i, j
        cdef float x0, x1, x2, y0, y1, y2


        for j in range(samples.subchannels):

            x1 = self.last_x_1[j]
            x2 = self.last_x_2[j]

            y1 = self.last_y_1[j]
            y2 = self.last_y_2[j]

            for i in range(samples.length):
                x0 = samples.samples[i * samples.subchannels + j]
                y0 = self.cx0 * x0 + self.cx1 * x1 + self.cx2 * x2 - self.cy1 * y1 - self.cy2 * y2

                result.samples[i * samples.subchannels + j] = y0

                x2 = x1
                x1 = x0

                y2 = y1
                y1 = y0

            self.last_x_1[j] = x1
            self.last_x_2[j] = x2

            self.last_y_1[j] = y1
            self.last_y_2[j] = y2

        return result



def to_audio_filter(o):
    """
    Converts a Python object to an AudioFilter. This expands lists into
    Sequence objects, passes AudioFilter objects through, and raises
    an exception for anything else.
    """

    if isinstance(o, AudioFilter):
        return o

    if isinstance(o, list):
        return Sequence(o)

    raise TypeError("Expected an AudioFilter, got {!r}.".format(o))



cdef void apply_audio_filter(AudioFilter af, float *samples, int subchannels, int length) nogil:

    cdef SampleBuffer *input_buffer
    cdef SampleBuffer *result_buffer
    cdef int i, j

    input_buffer = allocate_buffer(subchannels, length)

    memcpy(input_buffer.samples, samples, length * subchannels * sizeof(float))

    result_buffer = af.apply(input_buffer)

    memcpy(samples, result_buffer.samples, length * subchannels * sizeof(float))

    free_buffer(input_buffer)
    free_buffer(result_buffer)

    return


cdef apply_audio_filter_type *get_apply_audio_filter():
    return <apply_audio_filter_type *> apply_audio_filter
