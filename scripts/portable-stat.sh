#!/bin/sh

# Print one file metadata value using the first stat implementation that both
# exits successfully and returns a plausibly shaped value.
#
# Two properties matter, and the second is the one that caused a production
# incident: GNU stat's -f flag means "filesystem status", not "format", so on
# GNU/Linux `stat -f '%u' file` writes several lines of filesystem detail to
# stdout and *then* exits 1. Chaining the probes as
#
#     owner=$(stat -f '%u' "$f" || stat -c '%u' "$f")
#
# therefore captures the failed probe's output concatenated with the real uid,
# which no comparison can match -- the config validator read that as "the file
# is owned by someone else" and refused to run.
#
# So: capture each probe on its own, accept it only if it exits zero, and then
# check the shape of what came back. A probe that exits zero with unexpected
# output is rejected rather than trusted.
rde_stat() {
  rde_stat_field=$1
  rde_stat_path=$2

  case $rde_stat_field in
    owner)
      rde_stat_gnu_format=%u
      rde_stat_bsd_format=%u
      rde_stat_shape=decimal
      ;;
    mode)
      rde_stat_gnu_format=%a
      rde_stat_bsd_format=%Lp
      rde_stat_shape=octal
      ;;
    *)
      return 1
      ;;
  esac

  # GNU first: this is the form that is wrong-but-successful nowhere, whereas
  # the BSD form is wrong-but-noisy on GNU.
  if rde_stat_value=$(stat -c "$rde_stat_gnu_format" "$rde_stat_path" 2>/dev/null) &&
    rde_stat_is "$rde_stat_shape" "$rde_stat_value"; then
    printf '%s\n' "$rde_stat_value"
    return 0
  fi

  # The previous capture is discarded with its subshell; nothing it printed can
  # reach the value below.
  if rde_stat_value=$(stat -f "$rde_stat_bsd_format" "$rde_stat_path" 2>/dev/null) &&
    rde_stat_is "$rde_stat_shape" "$rde_stat_value"; then
    printf '%s\n' "$rde_stat_value"
    return 0
  fi

  return 1
}

# Reject anything that is not a bare number of the expected base. Multi-line
# output fails here too, since a newline is not a digit.
rde_stat_is() {
  case $1 in
    decimal)
      case $2 in
        '' | *[!0-9]*) return 1 ;;
      esac
      ;;
    octal)
      case $2 in
        '' | *[!0-7]*) return 1 ;;
      esac
      ;;
    *)
      return 1
      ;;
  esac
  return 0
}
