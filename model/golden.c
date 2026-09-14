/* Golden model for the uNPU 4x4 weight-stationary INT8 matmul.
 *
 * Host-side tool (plain C99, not the bare-metal fw/ subset). Computes
 * reference C = A * W for the fixed 4-wide contraction dimension and emits
 * $readmemh-compatible hex vector files under model/vectors/, so RTL
 * testbenches have one trusted oracle instead of each hand-deriving
 * expected values. See docs/session-handoff.md and CLAUDE.md for the
 * timing contract and register/accumulator width constraints this mirrors.
 *
 * Vector file format, task 002 vs. task 006: identity/all_ones/cross_terms,
 * random_signed, random_unsigned (M=4 always) write <name>_a.hex as exactly
 * M times 4 = 16 bytes, per task 002's original contract. The seq_ and crv_
 * cases (task 006, M possibly < 4) write <name>_a.hex as a fixed 16 bytes
 * (4 rows x 4 cols), zero-padded outside the true M x K_true submatrix --
 * unpu_seq's a_src port is a fixed 4x4 direct-forced input, so its
 * testbench needs the full grid on disk, not just the M real rows. The two
 * conventions agree exactly when M is 4, so this is a widening for M<4
 * cases, not a break of the M=4 cases' existing files.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <io.h> /* mkdir() prototype on this toolchain */
#endif

#define K 4    /* contraction dimension, fixed by the 4x4 array */
#define J 4    /* output columns, fixed by the 4x4 array */
#define MAXM 4 /* array height cap -- M is always <=4 at runtime (handoff §6) */

/* Named npu_mode_t, not mode_t -- some toolchains' sys/stat.h already
 * defines mode_t (permission bits), and this collides with it. */
typedef enum { MODE_SIGNED, MODE_UNSIGNED } npu_mode_t;

/* Fixed, deterministic PRNG (xorshift32) rather than libc rand() -- so
 * random vectors are bit-for-bit reproducible across machines/compilers/
 * libc versions. A regression that depends on "random" input must be able
 * to regenerate the exact same input every time. */
static uint32_t xorshift32(uint32_t *state) {
  uint32_t x = *state;
  x ^= x << 13;
  x ^= x >> 17;
  x ^= x << 5;
  *state = x;
  return x;
}

/* Multiply-accumulate for one product, matching unpu_pe's mode_unsigned
 * semantics: two's-complement signed when MODE_SIGNED, unsigned when
 * MODE_UNSIGNED. Accumulation itself is always plain 32-bit signed. */
static int32_t mac_product(uint8_t a, uint8_t w, npu_mode_t mode) {
  if (mode == MODE_UNSIGNED) {
    return (int32_t)((uint32_t)a * (uint32_t)w);
  } else {
    int8_t as = (int8_t)a;
    int8_t ws = (int8_t)w;
    return (int32_t)as * (int32_t)ws;
  }
}

/* C[m][j] = sum_k A[m][k] * W[k][j], A is M x K, W is K x J, C is M x J.
 * Callers with K_true/N_true < 4 (task 006) zero-pad W outside the true
 * K_true x N_true submatrix before calling this -- a zero weight nulls the
 * product regardless of the paired activation, so matmul() itself needs no
 * notion of K_true/N_true; it just contracts over the full fixed K=4/J=4
 * every time, same as before task 006. */
static void matmul(const uint8_t *A, int M, const uint8_t *W, int32_t *C,
                    npu_mode_t mode) {
  int m, j, k;
  for (m = 0; m < M; m++) {
    for (j = 0; j < J; j++) {
      int32_t acc = 0;
      for (k = 0; k < K; k++) {
        acc += mac_product(A[m * K + k], W[k * J + j], mode);
      }
      C[m * J + j] = acc;
    }
  }
}

static int ensure_dir(const char *path) {
  struct stat st;
  if (stat(path, &st) == 0) {
    return 0; /* already exists */
  }
  /* mkdir's signature is platform-dependent (POSIX takes a mode_t
   * permission argument; this MinGW toolchain's does not). */
#ifdef _WIN32
  return mkdir(path);
#else
  return mkdir(path, 0755);
#endif
}

static int write_hex8(const char *path, const uint8_t *vals, int n) {
  FILE *f = fopen(path, "w");
  int i;
  if (!f) {
    fprintf(stderr, "error: could not open %s for writing\n", path);
    return -1;
  }
  for (i = 0; i < n; i++) {
    fprintf(f, "%02x\n", vals[i]);
  }
  fclose(f);
  return 0;
}

static int write_hex32(const char *path, const int32_t *vals, int n) {
  FILE *f = fopen(path, "w");
  int i;
  if (!f) {
    fprintf(stderr, "error: could not open %s for writing\n", path);
    return -1;
  }
  for (i = 0; i < n; i++) {
    fprintf(f, "%08x\n", (uint32_t)vals[i]);
  }
  fclose(f);
  return 0;
}

/* Meta-file format, task 006: extends the original 2-line M=/MODE= format
 * (task 002) with two more lines APPENDED after MODE=, never inserted
 * before it. tb/unpu_stall_tb.sv parses this file with
 * $fscanf(fd, "M=%d\nMODE=%s\n", ...) and stops reading after line 2 --
 * appending after, rather than reordering or inserting, leaves that parse
 * untouched on regenerated files. See docs/planning/tasks/006-sequencer.md
 * for the full rationale; do not reorder these lines. */
static int write_meta(const char *path, int M, npu_mode_t mode, int K_true,
                       int N_true) {
  FILE *f = fopen(path, "w");
  if (!f) {
    fprintf(stderr, "error: could not open %s for writing\n", path);
    return -1;
  }
  fprintf(f, "M=%d\n", M);
  fprintf(f, "MODE=%s\n", mode == MODE_UNSIGNED ? "UNSIGNED" : "SIGNED");
  fprintf(f, "K=%d\n", K_true);
  fprintf(f, "N=%d\n", N_true);
  fclose(f);
  return 0;
}

/* Computes C, writes <name>_a.hex, <name>_w.hex, <name>_c.hex and
 * <name>_meta.txt under model/vectors/. Returns the computed C in *C_out
 * (caller-allocated, M*J int32_t) so callers can self-check before any
 * file gets written by the caller's own logic (this function writes
 * unconditionally -- self-checking against hand-computed expectations
 * happens in main(), before calling this, for the required cases).
 *
 * A is always read/written as a fixed MAXM*K (16) byte buffer regardless of
 * M -- see the file header comment on the task 002 vs. task 006 vector
 * format. K_true/N_true are recorded in the meta file only (matmul() and
 * the A/W buffers already encode the zero-padding structurally).
 */
static int generate_case(const char *name, const uint8_t *A, int M,
                          const uint8_t *W, npu_mode_t mode, int32_t *C_out,
                          int K_true, int N_true) {
  char path[256];
  int rc = 0;

  matmul(A, M, W, C_out, mode);

  snprintf(path, sizeof(path), "model/vectors/%s_a.hex", name);
  rc |= write_hex8(path, A, MAXM * K);

  snprintf(path, sizeof(path), "model/vectors/%s_w.hex", name);
  rc |= write_hex8(path, W, K * J);

  snprintf(path, sizeof(path), "model/vectors/%s_c.hex", name);
  rc |= write_hex32(path, C_out, M * J);

  snprintf(path, sizeof(path), "model/vectors/%s_meta.txt", name);
  rc |= write_meta(path, M, mode, K_true, N_true);

  return rc;
}

/* Fills A (M*K bytes) and W (K*J bytes) with PRNG output covering the full
 * 0x00-0xFF byte range, seeded deterministically from 'seed'. There is no
 * independent hand-computed expectation for random data -- matmul() is
 * itself the oracle here, and it was already validated against hand-
 * computed expectations by the 'identity' and 'all_ones' cases above, so
 * random cases lean on that trust rather than re-deriving it. */
static void fill_random_case(uint8_t *A, int M, uint8_t *W, uint32_t seed) {
  uint32_t state = seed;
  int i;
  for (i = 0; i < M * K; i++) {
    A[i] = (uint8_t)(xorshift32(&state) & 0xFF);
  }
  for (i = 0; i < K * J; i++) {
    W[i] = (uint8_t)(xorshift32(&state) & 0xFF);
  }
}

/* Task 006 CRV filler: draws full-byte-range random data for a M x K_true /
 * K_true x N_true submatrix into fixed 4x4 (16-byte) A_full/W_full buffers,
 * zero-padding everything outside that submatrix. Unlike fill_random_case,
 * 'state' is threaded through by the caller across the whole 64-case batch
 * (one running xorshift32 stream, not re-seeded per case) -- draws are only
 * made for true (non-padded) cells, in row-major order, so the sequence is
 * still fully deterministic for a given base seed regardless of the drawn
 * M/K_true/N_true shapes. */
static void fill_crv_case(uint8_t *A_full, uint8_t *W_full, int M,
                           int K_true, int N_true, uint32_t *state) {
  int m, k, j;
  for (m = 0; m < MAXM; m++) {
    for (k = 0; k < K; k++) {
      A_full[m * K + k] =
          (m < M && k < K_true) ? (uint8_t)(xorshift32(state) & 0xFF) : 0;
    }
  }
  for (k = 0; k < K; k++) {
    for (j = 0; j < J; j++) {
      W_full[k * J + j] =
          (k < K_true && j < N_true) ? (uint8_t)(xorshift32(state) & 0xFF)
                                      : 0;
    }
  }
}

int main(void) {
  const int M = 4;
  uint8_t A_identity[M * K];
  uint8_t W_identity[K * J];
  int32_t C_identity[M * J];

  uint8_t A_ones[M * K];
  uint8_t W_ones[K * J];
  int32_t C_ones[M * J];

  uint8_t A_cross[M * K];
  uint8_t W_cross[K * J];
  int32_t C_cross[M * J];

  uint8_t A_rand_s[M * K];
  uint8_t W_rand_s[K * J];
  int32_t C_rand_s[M * J];

  uint8_t A_rand_u[M * K];
  uint8_t W_rand_u[K * J];
  int32_t C_rand_u[M * J];

  int m, k, j;
  int fail = 0;

  /* ---- Case 1: identity ---- */
  for (k = 0; k < K; k++) {
    for (j = 0; j < J; j++) {
      W_identity[k * J + j] = (k == j) ? 1 : 0;
    }
  }
  for (m = 0; m < M; m++) {
    for (k = 0; k < K; k++) {
      A_identity[m * K + k] = (uint8_t)((m * K + k) % 128);
    }
  }
  matmul(A_identity, M, W_identity, C_identity, MODE_SIGNED);

  /* Hand-computed expectation: C == A exactly (extended to 32-bit). */
  for (m = 0; m < M && !fail; m++) {
    for (j = 0; j < J; j++) {
      int32_t expected = (int32_t)A_identity[m * K + j];
      if (C_identity[m * J + j] != expected) {
        fprintf(stderr,
                "FAIL identity: C[%d][%d]=%d expected %d\n", m, j,
                C_identity[m * J + j], expected);
        fail = 1;
      }
    }
  }
  if (fail) {
    fprintf(stderr, "golden model self-check failed for 'identity'; no vectors written\n");
    return 1;
  }
  printf("PASS: identity self-check (C == A)\n");

  /* ---- Case 2: all_ones ---- */
  for (k = 0; k < K; k++) {
    for (j = 0; j < J; j++) {
      W_ones[k * J + j] = 1;
    }
  }
  for (m = 0; m < M; m++) {
    for (k = 0; k < K; k++) {
      A_ones[m * K + k] = 1;
    }
  }
  matmul(A_ones, M, W_ones, C_ones, MODE_SIGNED);

  /* Hand-computed expectation: every C[m][j] == 4. */
  for (m = 0; m < M && !fail; m++) {
    for (j = 0; j < J; j++) {
      if (C_ones[m * J + j] != 4) {
        fprintf(stderr,
                "FAIL all_ones: C[%d][%d]=%d expected 4\n", m, j,
                C_ones[m * J + j]);
        fail = 1;
      }
    }
  }
  if (fail) {
    fprintf(stderr, "golden model self-check failed for 'all_ones'; no vectors written\n");
    return 1;
  }
  printf("PASS: all_ones self-check (every C[m][j] == 4)\n");

  /* ---- Case 3: cross_terms -- each output is a sum of two distinct
   * nonzero products, every value differs, so a row/column swap in the
   * skew/de-skew wiring changes the answer (unlike 'identity' or
   * 'all_ones', see docs/planning/tasks/004-skew-deskew.md). ---- */
  {
    /* Sizes below use the literal 4 (== M here) rather than M itself: M is
     * a local (non-constant-expression) variable in C, so it cannot size a
     * static initialized array. */
    static const uint8_t A_cross_init[4 * K] = {
      1,  2,  3,  4,
      5,  6,  7,  8,
      9,  10, 11, 12,
      13, 14, 15, 16
    };
    static const uint8_t W_cross_init[K * J] = {
      1, 0, 2, 0,
      0, 1, 0, 2,
      2, 0, 1, 0,
      0, 2, 0, 1
    };
    static const int32_t C_cross_expected[4 * J] = {
      7,  10, 5,  8,
      19, 22, 17, 20,
      31, 34, 29, 32,
      43, 46, 41, 44
    };
    memcpy(A_cross, A_cross_init, sizeof(A_cross_init));
    memcpy(W_cross, W_cross_init, sizeof(W_cross_init));
    matmul(A_cross, M, W_cross, C_cross, MODE_SIGNED);

    for (m = 0; m < M && !fail; m++) {
      for (j = 0; j < J; j++) {
        if (C_cross[m * J + j] != C_cross_expected[m * J + j]) {
          fprintf(stderr,
                  "FAIL cross_terms: C[%d][%d]=%d expected %d\n", m, j,
                  C_cross[m * J + j], C_cross_expected[m * J + j]);
          fail = 1;
        }
      }
    }
    if (fail) {
      fprintf(stderr, "golden model self-check failed for 'cross_terms'; no vectors written\n");
      return 1;
    }
    printf("PASS: cross_terms self-check (matches hand-computed table)\n");
  }

  /* ---- Case 4: random_signed -- full-byte-range random A/W, signed mode ---- */
  fill_random_case(A_rand_s, M, W_rand_s, 0xC0FFEEu);
  matmul(A_rand_s, M, W_rand_s, C_rand_s, MODE_SIGNED);
  printf("PASS: random_signed generated (seed 0xC0FFEE, oracle = matmul())\n");

  /* ---- Case 4: random_unsigned -- full-byte-range random A/W, unsigned mode ---- */
  fill_random_case(A_rand_u, M, W_rand_u, 0xDEADBEEFu);
  matmul(A_rand_u, M, W_rand_u, C_rand_u, MODE_UNSIGNED);
  printf("PASS: random_unsigned generated (seed 0xDEADBEEF, oracle = matmul())\n");

  /* All checks/generation passed -- now write vector files. */
  if (ensure_dir("model/vectors") != 0) {
    fprintf(stderr, "error: could not create model/vectors\n");
    return 1;
  }

  if (generate_case("identity", A_identity, M, W_identity, MODE_SIGNED,
                     C_identity, K, J) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'identity'\n");
    return 1;
  }
  printf("wrote model/vectors/identity_{a,w,c}.hex + identity_meta.txt\n");

  if (generate_case("all_ones", A_ones, M, W_ones, MODE_SIGNED,
                     C_ones, K, J) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'all_ones'\n");
    return 1;
  }
  printf("wrote model/vectors/all_ones_{a,w,c}.hex + all_ones_meta.txt\n");

  if (generate_case("cross_terms", A_cross, M, W_cross, MODE_SIGNED,
                     C_cross, K, J) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'cross_terms'\n");
    return 1;
  }
  printf("wrote model/vectors/cross_terms_{a,w,c}.hex + cross_terms_meta.txt\n");

  if (generate_case("random_signed", A_rand_s, M, W_rand_s, MODE_SIGNED,
                     C_rand_s, K, J) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'random_signed'\n");
    return 1;
  }
  printf("wrote model/vectors/random_signed_{a,w,c}.hex + random_signed_meta.txt\n");

  if (generate_case("random_unsigned", A_rand_u, M, W_rand_u, MODE_UNSIGNED,
                     C_rand_u, K, J) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'random_unsigned'\n");
    return 1;
  }
  printf("wrote model/vectors/random_unsigned_{a,w,c}.hex + random_unsigned_meta.txt\n");

  /* ---- Task 006 directed cases: seq_m1/seq_k1/seq_n1/seq_mixed --
   * exercise M<4, K<4, N<4 and a non-square/non-multiple-of-4 shape, none
   * of which the five cases above touch. Small, distinct, nonzero values
   * (not all-ones/identity patterns -- those already prove wiring above);
   * self-checked by trusting matmul() directly, same precedent as
   * random_signed/random_unsigned. A/W are always fixed 4x4 (16-byte)
   * buffers, zero-padded outside each case's true M x K_true / K_true x
   * N_true submatrix -- see the file header comment. ---- */
  {
    /* seq_m1: M=1, K=4, N=4 -- only row 0 of A is real, rows 1-3 are
     * padding (unused by matmul(), zeroed for a clean hex dump). */
    static const uint8_t A_seq_m1[MAXM * K] = {
      3,  12, 45, 7,
      0,  0,  0,  0,
      0,  0,  0,  0,
      0,  0,  0,  0
    };
    static const uint8_t W_seq_m1[K * J] = {
      2, 9, 1, 6,
      4, 3, 8, 5,
      7, 1, 2, 9,
      6, 4, 3, 1
    };
    int32_t C_seq_m1[1 * J];

    if (generate_case("seq_m1", A_seq_m1, 1, W_seq_m1, MODE_SIGNED,
                       C_seq_m1, 4, 4) != 0) {
      fprintf(stderr, "error: failed writing vectors for 'seq_m1'\n");
      return 1;
    }
    printf("PASS: seq_m1 generated (M=1,K=4,N=4, oracle = matmul())\n");
    printf("wrote model/vectors/seq_m1_{a,w,c}.hex + seq_m1_meta.txt\n");
  }

  {
    /* seq_k1: M=4, K=1, N=4 -- only column 0 of A and row 0 of W are real;
     * A's columns 1-3 are zeroed for clarity (the zero W rows already null
     * those products on their own) and W's rows 1-3 are the true K
     * padding. */
    static const uint8_t A_seq_k1[MAXM * K] = {
      5,  0, 0, 0,
      9,  0, 0, 0,
      2,  0, 0, 0,
      14, 0, 0, 0
    };
    static const uint8_t W_seq_k1[K * J] = {
      3, 7, 2, 5,
      0, 0, 0, 0,
      0, 0, 0, 0,
      0, 0, 0, 0
    };
    int32_t C_seq_k1[4 * J];

    if (generate_case("seq_k1", A_seq_k1, 4, W_seq_k1, MODE_SIGNED,
                       C_seq_k1, 1, 4) != 0) {
      fprintf(stderr, "error: failed writing vectors for 'seq_k1'\n");
      return 1;
    }
    printf("PASS: seq_k1 generated (M=4,K=1,N=4, oracle = matmul())\n");
    printf("wrote model/vectors/seq_k1_{a,w,c}.hex + seq_k1_meta.txt\n");
  }

  {
    /* seq_n1: M=4, K=4, N=1 -- only column 0 of W is real; columns 1-3 are
     * the true N padding. A is full 4x4, all of K used. */
    static const uint8_t A_seq_n1[MAXM * K] = {
      4, 8, 1, 6,
      9, 2, 7, 3,
      5, 10, 4, 8,
      12, 1, 6, 9
    };
    static const uint8_t W_seq_n1[K * J] = {
      3, 0, 0, 0,
      5, 0, 0, 0,
      2, 0, 0, 0,
      7, 0, 0, 0
    };
    int32_t C_seq_n1[4 * J];

    if (generate_case("seq_n1", A_seq_n1, 4, W_seq_n1, MODE_SIGNED,
                       C_seq_n1, 4, 1) != 0) {
      fprintf(stderr, "error: failed writing vectors for 'seq_n1'\n");
      return 1;
    }
    printf("PASS: seq_n1 generated (M=4,K=4,N=1, oracle = matmul())\n");
    printf("wrote model/vectors/seq_n1_{a,w,c}.hex + seq_n1_meta.txt\n");
  }

  {
    /* seq_mixed: M=3, K=2, N=3 -- non-square, non-multiple-of-4-in-every-
     * dimension (plan.md step 8's explicit ask). Row 3 of A is M padding
     * (unused by matmul()); A's columns 2-3 and W's rows 2-3 are K
     * padding; W's column 3 is N padding. */
    static const uint8_t A_seq_mixed[MAXM * K] = {
      2, 5, 0, 0,
      7, 1, 0, 0,
      3, 9, 0, 0,
      0, 0, 0, 0
    };
    static const uint8_t W_seq_mixed[K * J] = {
      4, 6, 2, 0,
      3, 8, 5, 0,
      0, 0, 0, 0,
      0, 0, 0, 0
    };
    int32_t C_seq_mixed[3 * J];

    if (generate_case("seq_mixed", A_seq_mixed, 3, W_seq_mixed, MODE_SIGNED,
                       C_seq_mixed, 2, 3) != 0) {
      fprintf(stderr, "error: failed writing vectors for 'seq_mixed'\n");
      return 1;
    }
    printf("PASS: seq_mixed generated (M=3,K=2,N=3, oracle = matmul())\n");
    printf("wrote model/vectors/seq_mixed_{a,w,c}.hex + seq_mixed_meta.txt\n");
  }

  /* ---- Task 006 CRV batch: 64 pseudo-random cases, crv_0000..crv_0063,
   * one running xorshift32 stream seeded from 32'h5eed0006 (continuing the
   * per-task seed convention -- task 005 used 32'h5eed0005). Each case
   * draws its own M/K/N (uniform 1..4) and MODE, independently, from the
   * same running stream -- see fill_crv_case()'s header comment for why
   * that's still fully deterministic. ---- */
  {
    #define CRV_SEED 0x5eed0006u
    #define NUM_CRV  64
    uint32_t state = CRV_SEED;
    int idx;
    uint8_t A_crv[MAXM * K];
    uint8_t W_crv[K * J];
    int32_t C_crv[MAXM * J];
    char name[32];
    int crv_m, crv_k, crv_n;
    npu_mode_t crv_mode;

    printf("CRV base seed = 32'h%08x\n", (unsigned int)CRV_SEED);

    for (idx = 0; idx < NUM_CRV; idx++) {
      crv_m = (int)(xorshift32(&state) % 4) + 1;
      crv_k = (int)(xorshift32(&state) % 4) + 1;
      crv_n = (int)(xorshift32(&state) % 4) + 1;
      crv_mode = (xorshift32(&state) & 1u) ? MODE_UNSIGNED : MODE_SIGNED;

      fill_crv_case(A_crv, W_crv, crv_m, crv_k, crv_n, &state);

      snprintf(name, sizeof(name), "crv_%04d", idx);
      if (generate_case(name, A_crv, crv_m, W_crv, crv_mode, C_crv,
                         crv_k, crv_n) != 0) {
        fprintf(stderr, "error: failed writing vectors for '%s'\n", name);
        return 1;
      }
    }

    printf("wrote %d CRV case(s): model/vectors/crv_0000..crv_%04d_{a,w,c}.hex + _meta.txt\n",
           NUM_CRV, NUM_CRV - 1);
    #undef CRV_SEED
    #undef NUM_CRV
  }

  printf("ALL CASES PASSED AND WRITTEN\n");
  return 0;
}
