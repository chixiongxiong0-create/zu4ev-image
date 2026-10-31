/* Intercept mkdir: never creates host /run/lock. Build once per CLI. */
#define mkdir test_mkdir
#define main cli_main
#ifdef TEST_SENSOR
#include "sensorctl.c"
#else
#include "ispctl.c"
#endif
#undef main
#undef mkdir
#include <assert.h>
#include <sys/wait.h>
static int calls, injected_errno, forbid_mkdir;
int test_mkdir(const char *path, mode_t mode) {
  assert(!forbid_mkdir);
  assert(strcmp(path, "/run/lock") == 0);
  assert(mode == 0755);
  calls++;
  if (injected_errno) {
    errno = injected_errno;
    return -1;
  }
  return 0;
}
int main(void) {
  prepare_lock_directory(0);
  assert(calls == 0);
  prepare_lock_directory(1);
  assert(calls == 1);
  injected_errno = EEXIST;
  prepare_lock_directory(1);
  assert(calls == 2);
  pid_t child = fork();
  assert(child >= 0);
  if (!child) {
    injected_errno = EACCES;
    prepare_lock_directory(1);
    _exit(0);
  }
  int status;
  assert(waitpid(child, &status, 0) == child);
  assert(WIFEXITED(status) && WEXITSTATUS(status) != 0);
  char *help_args[] = {"cli", "--help", NULL};
  assert(cli_main(2, help_args) == 0);
  assert(calls == 2);
  char *empty_args[] = {"cli", NULL};
  assert(cli_main(1, empty_args) == 1);
  assert(calls == 2);
  child = fork();
  assert(child >= 0);
  if (!child) {
    forbid_mkdir = 1;
    char *invalid_args[] = {"cli", "read", "-1", NULL};
    (void)cli_main(3, invalid_args);
    _exit(0);
  }
  assert(waitpid(child, &status, 0) == child);
  assert(WIFEXITED(status) && WEXITSTATUS(status) == 1);
  puts("PASS default lock directory: create/EEXIST/error/explicit "
       "skip/help/noargs/invalidargs");
  return 0;
}
