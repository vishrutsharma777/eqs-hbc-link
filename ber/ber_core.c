/*
 * ber_core.c -- PRBS generation and self-synchronising BER checking, as a
 *               MATLAB MEX function.
 *
 * WHY C: resolving a 1e-6 error floor with a tight confidence bound needs
 * upwards of 1e7 transmitted bits. That is a per-bit shift-register loop
 * that does not vectorise, and it is the one part of this framework that a
 * MATLAB loop cannot carry. Everything else stays in MATLAB.
 *
 * USAGE
 *   bits            = ber_core('gen',     order, nbits, seed)
 *   [nerr, nchk]    = ber_core('check',   order, rxbits)
 *   nerr            = ber_core('compare', txbits, rxbits)
 *
 *   order  : 7, 9 or 15  (PRBS7 / PRBS9 / PRBS15)
 *   bits   : uint8 row vector of 0/1
 *
 * The checker is SELF-SYNCHRONISING, which is how a real bit-error-rate
 * tester works: the received bits are shifted into the local register, and
 * each incoming bit is compared against the one the register predicts. After
 * `order` bits the checker has locked to the incoming stream regardless of
 * where in the sequence it started, so no explicit bit-slip search is
 * needed. The first `order` bits are consumed by that lock and are excluded
 * from the error count -- hence nchk = nbits - order.
 *
 * ERROR MULTIPLICATION -- measured, not assumed. A single channel error is
 * counted THREE times by a self-synchronising checker: once when it is
 * compared, then once more as it passes each of the two feedback taps. The
 * factor is (number of taps + 1) = 3 for all three polynomials here, and
 * tests/testPrbs.m asserts it. It holds only while errors are sparse enough
 * not to overlap in the register, i.e. BER << 1/order; above that the factor
 * saturates below 3. berCount.m divides it out and refuses the correction
 * outside its valid range.
 *
 * Because the link simulator knows the transmitted bits exactly, the default
 * BER path uses the 'compare' op instead, which has no multiplication at all.
 * 'check' is the hardware-in-the-loop path, for when only the received
 * stream is available -- which is the situation on real silicon.
 *
 * Polynomials (Fibonacci LFSR, feedback = x^order + x^tap + 1):
 *   PRBS7  : x^7  + x^6  + 1
 *   PRBS9  : x^9  + x^5  + 1
 *   PRBS15 : x^15 + x^14 + 1
 */

#include "mex.h"
#include <string.h>

static int tap_for_order(int order)
{
    switch (order) {
        case 7:  return 6;
        case 9:  return 5;
        case 15: return 14;
        default: return -1;
    }
}

/* ------------------------------------------------------------------ */
static void prbs_gen(unsigned char *out, mwSize n, int order, unsigned int seed)
{
    int tap = tap_for_order(order);
    unsigned int mask = (1u << order) - 1u;
    unsigned int reg  = seed & mask;
    mwSize i;

    if (reg == 0u) reg = 1u;          /* all-zero is a lockup state */

    for (i = 0; i < n; ++i) {
        unsigned int fb = ((reg >> (order - 1)) ^ (reg >> (tap - 1))) & 1u;
        reg = ((reg << 1) | fb) & mask;
        out[i] = (unsigned char)fb;
    }
}

/* ------------------------------------------------------------------ */
static void prbs_check(const unsigned char *rx, mwSize n, int order,
                       double *nerr, double *nchk)
{
    int tap = tap_for_order(order);
    unsigned int mask = (1u << order) - 1u;
    unsigned int reg  = 0u;
    mwSize i;
    double errs = 0.0;

    if (n <= (mwSize)order) {
        *nerr = 0.0;
        *nchk = 0.0;
        return;
    }

    /* Lock: shift the first `order` received bits in, uncounted. */
    for (i = 0; i < (mwSize)order; ++i)
        reg = ((reg << 1) | (rx[i] & 1u)) & mask;

    for (i = (mwSize)order; i < n; ++i) {
        unsigned int pred = ((reg >> (order - 1)) ^ (reg >> (tap - 1))) & 1u;
        unsigned int got  = rx[i] & 1u;
        if (pred != got) errs += 1.0;
        reg = ((reg << 1) | got) & mask;   /* self-sync: shift in RECEIVED */
    }

    *nerr = errs;
    *nchk = (double)(n - (mwSize)order);
}

/* ------------------------------------------------------------------ */
void mexFunction(int nlhs, mxArray *plhs[], int nrhs, const mxArray *prhs[])
{
    char op[16];

    if (nrhs < 1 || !mxIsChar(prhs[0]))
        mexErrMsgIdAndTxt("ber_core:usage", "First argument must be 'gen' or 'check'.");
    if (mxGetString(prhs[0], op, sizeof(op)) != 0)
        mexErrMsgIdAndTxt("ber_core:usage", "Could not read operation string.");

    if (strcmp(op, "gen") == 0) {
        int order;
        mwSize nbits;
        unsigned int seed;
        unsigned char *out;

        if (nrhs != 4)
            mexErrMsgIdAndTxt("ber_core:usage",
                "bits = ber_core('gen', order, nbits, seed)");

        order = (int)mxGetScalar(prhs[1]);
        nbits = (mwSize)mxGetScalar(prhs[2]);
        seed  = (unsigned int)mxGetScalar(prhs[3]);

        if (tap_for_order(order) < 0)
            mexErrMsgIdAndTxt("ber_core:order", "order must be 7, 9 or 15.");

        plhs[0] = mxCreateNumericMatrix(1, nbits, mxUINT8_CLASS, mxREAL);
        out = (unsigned char *)mxGetData(plhs[0]);
        prbs_gen(out, nbits, order, seed);

    } else if (strcmp(op, "check") == 0) {
        int order;
        mwSize n;
        const unsigned char *rx;
        double nerr = 0.0, nchk = 0.0;

        if (nrhs != 3)
            mexErrMsgIdAndTxt("ber_core:usage",
                "[nerr,nchk] = ber_core('check', order, rxbits)");

        order = (int)mxGetScalar(prhs[1]);
        if (tap_for_order(order) < 0)
            mexErrMsgIdAndTxt("ber_core:order", "order must be 7, 9 or 15.");

        if (!mxIsUint8(prhs[2]) && !mxIsLogical(prhs[2]))
            mexErrMsgIdAndTxt("ber_core:type", "rxbits must be uint8 or logical.");

        n  = mxGetNumberOfElements(prhs[2]);
        rx = (const unsigned char *)mxGetData(prhs[2]);

        prbs_check(rx, n, order, &nerr, &nchk);

        plhs[0] = mxCreateDoubleScalar(nerr);
        if (nlhs > 1) plhs[1] = mxCreateDoubleScalar(nchk);

    } else if (strcmp(op, "compare") == 0) {
        mwSize n, i;
        const unsigned char *tx, *rx;
        double errs = 0.0;

        if (nrhs != 3)
            mexErrMsgIdAndTxt("ber_core:usage",
                "nerr = ber_core('compare', txbits, rxbits)");
        if ((!mxIsUint8(prhs[1]) && !mxIsLogical(prhs[1])) ||
            (!mxIsUint8(prhs[2]) && !mxIsLogical(prhs[2])))
            mexErrMsgIdAndTxt("ber_core:type", "bit vectors must be uint8 or logical.");

        n = mxGetNumberOfElements(prhs[1]);
        if (mxGetNumberOfElements(prhs[2]) != n)
            mexErrMsgIdAndTxt("ber_core:size", "tx and rx must be the same length.");

        tx = (const unsigned char *)mxGetData(prhs[1]);
        rx = (const unsigned char *)mxGetData(prhs[2]);

        for (i = 0; i < n; ++i)
            if ((tx[i] & 1u) != (rx[i] & 1u)) errs += 1.0;

        plhs[0] = mxCreateDoubleScalar(errs);
        if (nlhs > 1) plhs[1] = mxCreateDoubleScalar((double)n);

    } else {
        mexErrMsgIdAndTxt("ber_core:usage", "Unknown operation '%s'.", op);
    }
}
