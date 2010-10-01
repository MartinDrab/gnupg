/* util.h - Utility functions for GnuPG
 * Copyright (C) 2001, 2002, 2003, 2004, 2009 Free Software Foundation, Inc.
 *
 * This file is part of GnuPG.
 *
 * GnuPG is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 3 of the License, or
 * (at your option) any later version.
 *
 * GnuPG is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, see <http://www.gnu.org/licenses/>.
 */

#ifndef GNUPG_COMMON_UTIL_H
#define GNUPG_COMMON_UTIL_H

#include <gcrypt.h> /* We need this for the memory function protos. */
#include <errno.h>  /* We need errno.  */
#include <gpg-error.h> /* We need gpg_error_t. */
/* Add error codes available only in newer versions of libgpg-error.  */
#ifndef GPG_ERR_MISSING_KEY
#define GPG_ERR_MISSING_KEY 181
#endif
#ifndef GPG_ERR_LIMIT_REACHED
#define GPG_ERR_LIMIT_REACHED 183
#endif
#ifndef GPG_ERR_NOT_INITIALIZED
#define GPG_ERR_NOT_INITIALIZED 184
#endif
#ifndef GPG_ERR_MISSING_ISSUER_CERT
#define GPG_ERR_MISSING_ISSUER_CERT 185
#endif
#ifndef GPG_ERR_FULLY_CANCELED
#define GPG_ERR_FULLY_CANCELED 198
#endif


/* Hash function used with libksba. */
#define HASH_FNC ((void (*)(void *, const void*,size_t))gcry_md_write)

/* Estream replaces most uses of stdio.  */
#include "../common/estream.h"
#include "../common/estream-printf.h"

/* Get all the stuff from jnlib. */
#include "../common/logging.h"
#include "../common/argparse.h"
#include "../common/stringhelp.h"
#include "../common/mischelp.h"
#include "../common/strlist.h"
#include "../common/dotlock.h"
#include "../common/utf8conv.h"
#include "../common/dynload.h"

#include "init.h"
#include "gettime.h"

/* Redefine asprintf by our estream version which uses our own memory
   allocator..  */
#define asprintf estream_asprintf
#define vasprintf estream_vasprintf

/* Due to a bug in mingw32's snprintf related to the 'l' modifier and
   for increased portability we use our snprintf on all systems. */
#define snprintf estream_snprintf


/* GCC attributes.  */
#if __GNUC__ >= 4 
# define GNUPG_GCC_A_SENTINEL(a) __attribute__ ((sentinel(a)))
#else
# define GNUPG_GCC_A_SENTINEL(a) 
#endif


/* We need this type even if we are not using libreadline and or we
   did not include libreadline in the current file. */
#ifndef GNUPG_LIBREADLINE_H_INCLUDED
typedef char **rl_completion_func_t (const char *, int, int);
#endif /*!GNUPG_LIBREADLINE_H_INCLUDED*/


/* Handy malloc macros - please use only them. */
#define xtrymalloc(a)    gcry_malloc ((a))
#define xtrymalloc_secure(a)  gcry_malloc_secure ((a))
#define xtrycalloc(a,b)  gcry_calloc ((a),(b))
#define xtrycalloc_secure(a,b)  gcry_calloc_secure ((a),(b))
#define xtryrealloc(a,b) gcry_realloc ((a),(b))
#define xtrystrdup(a)    gcry_strdup ((a))
#define xfree(a)         gcry_free ((a))
#define xfree_fnc        gcry_free

#define xmalloc(a)       gcry_xmalloc ((a))
#define xmalloc_secure(a)  gcry_xmalloc_secure ((a))
#define xcalloc(a,b)     gcry_xcalloc ((a),(b))
#define xcalloc_secure(a,b) gcry_xcalloc_secure ((a),(b))
#define xrealloc(a,b)    gcry_xrealloc ((a),(b))
#define xstrdup(a)       gcry_xstrdup ((a))

/* For compatibility with gpg 1.4 we also define these: */
#define xmalloc_clear(a) gcry_xcalloc (1, (a))
#define xmalloc_secure_clear(a) gcry_xcalloc_secure (1, (a))

/* Convenience function to return a gpg-error code for memory
   allocation failures.  This function makes sure that an error will
   be returned even if accidently ERRNO is not set.  */
static inline gpg_error_t
out_of_core (void)
{
  return gpg_error_from_syserror ();
}


/*-- signal.c --*/
void gnupg_init_signals (int mode, void (*fast_cleanup)(void));
void gnupg_block_all_signals (void);
void gnupg_unblock_all_signals (void);

/*-- yesno.c --*/
int answer_is_yes (const char *s);
int answer_is_yes_no_default (const char *s, int def_answer);
int answer_is_yes_no_quit (const char *s);
int answer_is_okay_cancel (const char *s, int def_answer);

/*-- xreadline.c --*/
ssize_t read_line (FILE *fp, 
                   char **addr_of_buffer, size_t *length_of_buffer,
                   size_t *max_length);


/*-- b64enc.c and b64dec.c --*/
struct b64state 
{ 
  unsigned int flags;
  int idx;
  int quad_count;
  FILE *fp;
  estream_t stream;
  char *title;
  unsigned char radbuf[4];
  u32 crc;
  int stop_seen:1;
  int invalid_encoding:1;
};

gpg_error_t b64enc_start (struct b64state *state, FILE *fp, const char *title);
gpg_error_t b64enc_start_es (struct b64state *state, estream_t fp,
                             const char *title);
gpg_error_t b64enc_write (struct b64state *state,
                          const void *buffer, size_t nbytes);
gpg_error_t b64enc_finish (struct b64state *state);

gpg_error_t b64dec_start (struct b64state *state, const char *title);
gpg_error_t b64dec_proc (struct b64state *state, void *buffer, size_t length,
                         size_t *r_nbytes);
gpg_error_t b64dec_finish (struct b64state *state);




/*-- sexputil.c */
gpg_error_t make_canon_sexp (gcry_sexp_t sexp,
                             unsigned char **r_buffer, size_t *r_buflen);
gpg_error_t make_canon_sexp_pad (gcry_sexp_t sexp, int secure,
                                 unsigned char **r_buffer, size_t *r_buflen);
gpg_error_t keygrip_from_canon_sexp (const unsigned char *key, size_t keylen,
                                     unsigned char *grip);
int cmp_simple_canon_sexp (const unsigned char *a, const unsigned char *b);
unsigned char *make_simple_sexp_from_hexstr (const char *line,
                                             size_t *nscanned);
int hash_algo_from_sigval (const unsigned char *sigval);
unsigned char *make_canon_sexp_from_rsa_pk (const void *m, size_t mlen,
                                            const void *e, size_t elen,
                                            size_t *r_len);
gpg_error_t get_rsa_pk_from_canon_sexp (const unsigned char *keydata,
                                        size_t keydatalen,
                                        unsigned char const **r_n, 
                                        size_t *r_nlen,
                                        unsigned char const **r_e, 
                                        size_t *r_elen);
gpg_error_t get_pk_algo_from_canon_sexp (const unsigned char *keydata,
                                         size_t keydatalen,
                                         int *r_algo);

/*-- convert.c --*/
int hex2bin (const char *string, void *buffer, size_t length);
int hexcolon2bin (const char *string, void *buffer, size_t length);
char *bin2hex (const void *buffer, size_t length, char *stringbuf);
char *bin2hexcolon (const void *buffer, size_t length, char *stringbuf);
const char *hex2str (const char *hexstring,
                     char *buffer, size_t bufsize, size_t *buflen);
char *hex2str_alloc (const char *hexstring, size_t *r_count);

/*-- percent.c --*/
char *percent_plus_escape (const char *string);
char *percent_plus_unescape (const char *string, int nulrepl);
char *percent_unescape (const char *string, int nulrepl);

size_t percent_plus_unescape_inplace (char *string, int nulrepl);
size_t percent_unescape_inplace (char *string, int nulrepl);


/*-- homedir.c --*/
const char *standard_homedir (void);
const char *default_homedir (void);
const char *gnupg_sysconfdir (void);
const char *gnupg_bindir (void);
const char *gnupg_libexecdir (void);
const char *gnupg_libdir (void);
const char *gnupg_datadir (void);
const char *gnupg_localedir (void);
const char *gnupg_cachedir (void);
const char *dirmngr_socket_name (void);

/* All module names.  We also include gpg and gpgsm for the sake for
   gpgconf. */
#define GNUPG_MODULE_NAME_AGENT        1
#define GNUPG_MODULE_NAME_PINENTRY     2
#define GNUPG_MODULE_NAME_SCDAEMON     3 
#define GNUPG_MODULE_NAME_DIRMNGR      4
#define GNUPG_MODULE_NAME_PROTECT_TOOL 5
#define GNUPG_MODULE_NAME_CHECK_PATTERN 6
#define GNUPG_MODULE_NAME_GPGSM         7
#define GNUPG_MODULE_NAME_GPG           8
#define GNUPG_MODULE_NAME_CONNECT_AGENT 9
#define GNUPG_MODULE_NAME_GPGCONF       10
#define GNUPG_MODULE_NAME_DIRMNGR_LDAP  11
const char *gnupg_module_name (int which);



/*-- gpgrlhelp.c --*/
void gnupg_rl_initialize (void);

/*-- helpfile.c --*/
char *gnupg_get_help_string (const char *key, int only_current_locale);

/*-- localename.c --*/
const char *gnupg_messages_locale_name (void);

/*-- miscellaneous.c --*/

/* This function is called at startup to tell libgcrypt to use our own
   logging subsystem. */
void setup_libgcrypt_logging (void);

/* Same as estream_asprintf but die on memory failure.  */
char *xasprintf (const char *fmt, ...) JNLIB_GCC_A_PRINTF(1,2);
/* This is now an alias to estream_asprintf.  */
char *xtryasprintf (const char *fmt, ...) JNLIB_GCC_A_PRINTF(1,2);

const char *print_fname_stdout (const char *s);
const char *print_fname_stdin (const char *s);
void print_utf8_buffer2 (estream_t fp, const void *p, size_t n, int delim);
void print_utf8_buffer (estream_t fp, const void *p, size_t n);
void print_hexstring (FILE *fp, const void *buffer, size_t length,
                      int reserved);
char *make_printable_string (const void *p, size_t n, int delim);

int is_file_compressed (const char *s, int *ret_rc);

int match_multistr (const char *multistr,const char *match);


/*-- Simple replacement functions. */
#ifndef HAVE_TTYNAME
/* Systems without ttyname (W32) will merely return NULL. */
static inline char *
ttyname (int fd) 
{
  (void)fd;
  return NULL;
}
#endif /* !HAVE_TTYNAME */

#ifdef HAVE_W32CE_SYSTEM
#define getpid() GetCurrentProcessId ()
char *_gnupg_getenv (const char *name); /* See sysutils.c */
#define getenv(a)  _gnupg_getenv ((a))
char *_gnupg_setenv (const char *name); /* See sysutils.c */
#define setenv(a,b,c)  _gnupg_setenv ((a),(b),(c))
int _gnupg_isatty (int fd);
#define gnupg_isatty(a)  _gnupg_isatty ((a))
#else
#define gnupg_isatty(a)  isatty ((a))
#endif



/*-- Macros to replace ctype ones to avoid locale problems. --*/
#define spacep(p)   (*(p) == ' ' || *(p) == '\t')
#define digitp(p)   (*(p) >= '0' && *(p) <= '9')
#define hexdigitp(a) (digitp (a)                     \
                      || (*(a) >= 'A' && *(a) <= 'F')  \
                      || (*(a) >= 'a' && *(a) <= 'f'))
  /* Note this isn't identical to a C locale isspace() without \f and
     \v, but works for the purposes used here. */
#define ascii_isspace(a) ((a)==' ' || (a)=='\n' || (a)=='\r' || (a)=='\t')

/* The atoi macros assume that the buffer has only valid digits. */
#define atoi_1(p)   (*(p) - '0' )
#define atoi_2(p)   ((atoi_1(p) * 10) + atoi_1((p)+1))
#define atoi_4(p)   ((atoi_2(p) * 100) + atoi_2((p)+2))
#define xtoi_1(p)   (*(p) <= '9'? (*(p)- '0'): \
                     *(p) <= 'F'? (*(p)-'A'+10):(*(p)-'a'+10))
#define xtoi_2(p)   ((xtoi_1(p) * 16) + xtoi_1((p)+1))
#define xtoi_4(p)   ((xtoi_2(p) * 256) + xtoi_2((p)+2))


/*-- Forward declaration of the commonly used server control structure.  */
/*   (We need it here as it is used by some callback prototypes.) */
struct server_control_s;
typedef struct server_control_s *ctrl_t;


#endif /*GNUPG_COMMON_UTIL_H*/
