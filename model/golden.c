/* Golden model for the uNPU 4x4 weight-stationary INT8 matmul.
 *
 * Host-side tool (plain C99, not the bare-metal fw/ subset). Computes
 * reference C = A * W for the fixed 4-wide contraction dimension and emits
 * $readmemh-compatible hex vector files under model/vectors/, so RTL
 * testbenches have one trusted oracle instead of each hand-deriving
 * expected values. See docs/session-handoff.md and CLAUDE.md for the
 * timing contract and register/accumulator width constraints this mirrors.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/stat.h>
#ifdef _WIN32
#include <io.h> /* mkdir() prototype on this toolchain */
#endif

#define K 4 /* contraction dimension, fixed by the 4x4 array */
#define J 4 /* output columns, fixed by the 4x4 array */

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

/* C[m][j] = sum_k A[m][k] * W[k][j], A is M x K, W is K x J, C is M x J. */
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

static int write_meta(const char *path, int M, npu_mode_t mode) {
  FILE *f = fopen(path, "w");
  if (!f) {
    fprintf(stderr, "error: could not open %s for writing\n", path);
    return -1;
  }
  fprintf(f, "M=%d\n", M);
  fprintf(f, "MODE=%s\n", mode == MODE_UNSIGNED ? "UNSIGNED" : "SIGNED");
  fclose(f);
  return 0;
}

/* Computes C, writes <name>_a.hex, <name>_w.hex, <name>_c.hex and
 * <name>_meta.txt under model/vectors/. Returns the computed C in *C_out
 * (caller-allocated, M*J int32_t) so callers can self-check before any
 * file gets written by the caller's own logic (this function writes
 * unconditionally -- self-checking against hand-computed expectations
 * happens in main(), before calling this, for the required cases).
 */
static int generate_case(const char *name, const uint8_t *A, int M,
                          const uint8_t *W, npu_mode_t mode, int32_t *C_out) {
  char path[256];
  int rc = 0;

  matmul(A, M, W, C_out, mode);

  snprintf(path, sizeof(path), "model/vectors/%s_a.hex", name);
  rc |= write_hex8(path, A, M * K);

  snprintf(path, sizeof(path), "model/vectors/%s_w.hex", name);
  rc |= write_hex8(path, W, K * J);

  snprintf(path, sizeof(path), "model/vectors/%s_c.hex", name);
  rc |= write_hex32(path, C_out, M * J);

  snprintf(path, sizeof(path), "model/vectors/%s_meta.txt", name);
  rc |= write_meta(path, M, mode);

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
                     C_identity) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'identity'\n");
    return 1;
  }
  printf("wrote model/vectors/identity_{a,w,c}.hex + identity_meta.txt\n");

  if (generate_case("all_ones", A_ones, M, W_ones, MODE_SIGNED,
                     C_ones) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'all_ones'\n");
    return 1;
  }
  printf("wrote model/vectors/all_ones_{a,w,c}.hex + all_ones_meta.txt\n");

  if (generate_case("cross_terms", A_cross, M, W_cross, MODE_SIGNED,
                     C_cross) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'cross_terms'\n");
    return 1;
  }
  printf("wrote model/vectors/cross_terms_{a,w,c}.hex + cross_terms_meta.txt\n");

  if (generate_case("random_signed", A_rand_s, M, W_rand_s, MODE_SIGNED,
                     C_rand_s) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'random_signed'\n");
    return 1;
  }
  printf("wrote model/vectors/random_signed_{a,w,c}.hex + random_signed_meta.txt\n");

  if (generate_case("random_unsigned", A_rand_u, M, W_rand_u, MODE_UNSIGNED,
                     C_rand_u) != 0) {
    fprintf(stderr, "error: failed writing vectors for 'random_unsigned'\n");
    return 1;
  }
  printf("wrote model/vectors/random_unsigned_{a,w,c}.hex + random_unsigned_meta.txt\n");

  printf("ALL CASES PASSED AND WRITTEN\n");
  return 0;
}
